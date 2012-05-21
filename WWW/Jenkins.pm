package WWW::Jenkins;
use strict;
use warnings;
#  Copyright 2012 Netflix, Inc.
#
#     Licensed under the Apache License, Version 2.0 (the "License");
#     you may not use this file except in compliance with the License.
#     You may obtain a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#     Unless required by applicable law or agreed to in writing, software
#     distributed under the License is distributed on an "AS IS" BASIS,
#     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#     See the License for the specific language governing permissions and
#     limitations under the License.

use WWW::Jenkins::Job;
use LWP::UserAgent qw();
use HTTP::Cookies qw();
use JSON::Syck qw();

our @CLEANUP;

sub new {
    my $class = shift;
    my $self = bless {
        # defaults
        stoplight => 0,
        user      => $ENV{USER},
        @_
    }, $class;

    my $UA = $self->{verbose}
        ? "WWW::Jenkins::UserAgent"
        : "LWP::UserAgent";
    
    $self->{ua} ||= $UA->new(
        cookie_jar => HTTP::Cookies->new(
            file => "$ENV{HOME}/.$self->{user}-cookies.txt",
            autosave => 1,
        )
    );

    $self->{baseuri} || die "baseuri option required";
    
    return $self;
}

sub jobs {
    my ($self,@jobs) = @_;
    
    my @out = ();
    for my $job ( @jobs ) {
        my $uri = "$self->{baseuri}/job/$job/api/json?depth=0&tree=name,inQueue,url,lastBuild[number,url],color";

        my $res = $self->{ua}->get($uri);
        my $data = JSON::Syck::Load($res->decoded_content());
        push @out, WWW::Jenkins::Job->new(%$data, jenkins => $self);
    }
    return wantarray ? @out : \@out;
}

sub views {
    my ($self,@views) = @_;
    
    my @out = ();
    for my $view ( @views ) {
        # turns A/B into A/view/B which is needed
        # in jenkins uri for subviews
        my $viewPath = join("/view/", split '/', $view);
        my $uri = "$self->{baseuri}/view/$viewPath/api/json?depth=1&tree=views[name,url],jobs[name,inQueue,url,lastBuild[number,url,timestamp,duration],color]";
        my $res = $self->{ua}->get($uri);
        my $data = JSON::Syck::Load($res->decoded_content());
        # we dont know if the view has subviews or it it has jobs, so try for both
        # and recurse if we find a subview
        if( $data->{jobs} ) {
            push @out, WWW::Jenkins::Job->new(%$_, jenkins => $self) for @{$data->{jobs}};
        }
        if( $data->{views} ) {
            push @out, $self->views("$view/$_->{name}") for @{$data->{views}};
        }
    }
    return wantarray ? @out : \@out;
}

sub queue {
    my ( $self ) = @_;
    my $uri = "$self->{baseuri}/queue/api/json?depth=0&tree=items[task[color,name,url],why,stuck]";
    my $res = $self->{ua}->get($uri);
    #print $res->decoded_content;
    my $data = JSON::Syck::Load($res->decoded_content());
    my %blocked;
    my %stuck;
    my @running;
    my @quieted;
    for my $item ( @{$data->{items}} ) {
        my $job = WWW::Jenkins::Job->new(
            %{$item->{task}},
            inQueue => 1,
            jenkins => $self
        );

        if( $item->{stuck} ) {
            if( $item->{why} =~ /([^ ]+) (is|are) offline/ ) {
                push @{$stuck{$1}}, $job;
            }
            else {
                warn "don't understand why something is stuck: $item->{why}\n";
            }
        }
        else {
            if( $item->{why} =~ /Waiting for next available executor on (.*)/ ) {
                push @{$blocked{$1}}, $job;
            }
            elsif( $item->{why} =~ /already in progress/ ) {
                push @running, $job;
            }
            elsif( $item->{why} =~ /quiet period/ ) {
                push @quieted, $job;
            }
            else {
                warn "don't understand why something is enqueued: $item->{why}\n";
            }
        }
    }
    return {
        blocked => \%blocked,
        stuck   => \%stuck,
        running => \@running,
        quieted => \@quieted,
    };
}

sub login {
    my ( $self ) = @_;
    return if $self->{logged_in};
    # FIXME there has to be a better way to tell if we
    # are already logged in ...
    # just load the page with the smallest content that I could find
    # and check for a "log in" string to indicate the user is not
    # logged in already
    my $res = $self->{ua}->get("$self->{baseuri}/user/$self->{user}/?");
    if ( $res->decoded_content =~ />log in</ ) {
        $res = $self->{ua}->post(
            "$self->{baseuri}/j_acegi_security_check", {
                j_username => $self->{user},
                j_password => $self->password(),
            }
        );
        $self->{ua}->get("$self->{baseuri}/user/$self->{user}/?"); 
        $self->{ua}->cookie_jar->scan(
            sub {
                my @args = @_;
                # dont discard cookies, so we dont get prompted for a password everytime
                $args[9] = 0;
                $self->{ua}->cookie_jar->set_cookie(@args);
            }
        );
    }
    $self->{logged_in}++;
    return;
}

sub stdio {
    my $self = shift;
    my ($in, $out);
    if( !-t STDIN || !-t STDOUT ) {
        # stdio missing, so try to use tty directly
        my $tty = "/dev/tty" if -e "/dev/tty";
        if( !$tty ) {
            my ($ttyBin) = grep { -x $_ } qw(/bin/tty /usr/bin/tty);
            if ( $ttyBin ) {
                $tty = qx{$ttyBin};
                chomp($tty);
            }
        }
        
        if( !$tty ) {
            die "Could not determine TTY to read password from, aborting";
        }
        open $in,  "<$tty" or die "Failed to open tty $tty for input: $!";
        open $out, ">$tty" or die "Failed to open tty $tty for output: $!";
    }
    else {
        # using stdio
        $in  = \*STDIN;
        $out = \*STDOUT;
    }
    return ($in, $out);
}

sub password {
    my ( $self ) = @_;
    if ( defined $self->{password} ) {
        if ( ref($self->{password}) eq 'CODE' ) {
            return $self->{password}->($self);
        }
        return $self->{password};
    }
    my ($in, $out) = $self->stdio;

    my $old = select $out;
    eval "use Term::ReadKey";
    if( $@ ) {
        # no readkey, so try for stty to turn off echoing
        my ($sttyBin) = grep { -x $_ } qw(/bin/stty /usr/bin/stty);
        if( $sttyBin ) {
            push @CLEANUP, sub {
                system($sttyBin, "echo");
            };
            system($sttyBin, "-echo");
        }
        else {
            die "Unable to disable echo on your tty while reading password, aborting";
        }
    }
    else { 
        # use readkey to turn off echoing
        push @CLEANUP, sub {
            Term::ReadKey::ReadMode("restore", $out);
        };
        Term::ReadKey::ReadMode("noecho", $out);
    }
    print $out "Jenkins Password [$self->{user}]: ";
    my $pass = <$in>;
    $CLEANUP[-1]->();
    print $out "\n";
    chomp($pass);
    select $old;
    return $pass;
}

END { 
    for my $cleaner ( @CLEANUP ) {
        $cleaner->();
    }
}

# silly class to make debugging easier
package WWW::Jenkins::UserAgent;
use base qw(LWP::UserAgent);

sub request {
    my $self = shift;
    my $req  = shift;
    my $resp = $self->SUPER::request($req, @_);
    print "======================================>\n";
    print $req->as_string;
    print "<======================================\n";
    print $resp->as_string;
    return $resp;
}
1;
