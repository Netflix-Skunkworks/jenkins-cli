package WWW::Jenkins::Job;

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

use strict;
use warnings;

sub new {
    my $class = shift;
    my $self = bless { @_ }, $class;
    for my $required ( qw(name jenkins url lastBuild color inQueue) ) {
        defined $self->{$required} || die "no $required parameter to WWW::Jenkins::Job->new()";
    }
    return $self;
}

sub j {
    return shift->{jenkins};
}

sub ua {
    return shift->j->{ua};
}

sub name {
    return shift->{"name"};
}

# turns the jenkins 'color' attribute into a color
# suitable for encoding in Term::ANSIColor.
# All aborted builds are marked as red
sub color {
    my ( $self ) = @_;
    my $color = $self->{color};
    $color =~ s/_anime$//;
    $color = "green" if $self->j->{stoplight} && $color eq 'blue';
    $color = 'faint' if $color eq 'disabled';
    $color = 'red'   if $color eq 'aborted';
    $color = 'faint' if $color eq 'grey';
    return $color;
}

sub start {
    my ( $self ) = @_;
    $self->j->login();
    my $resp = $self->ua->post("$self->{url}/build", {});
    if( $resp->is_error ) {
        die "Failed to start $self->{name}, got error: " . $resp->status_line;
    }
    return 1;
}

sub stop {
    my ( $self ) = @_;
    $self->j->login();
    my $resp = $self->ua->post("$self->{lastBuild}->{url}/stop", {});
    if( $resp->is_error ) {
        die "Failed to stop $self->{name}, got error: " . $resp->status_line;
    }
    return 1;
}

sub is_running {
    my ( $self ) = @_;
    return $self->{color} =~ /_anime/ ? 1 : 0;
}

sub is_queued {
    my ( $self ) = @_;
    return $self->{inQueue} ? 1 : 0;
}

sub was_aborted {
    my ( $self ) = @_;
    return $self->{color} eq 'aborted';
}

sub wipeout {
    my ( $self ) = @_;
    $self->j->login();
    my $resp = $self->ua->post("$self->{url}/doWipeOutWorkspace", {});
    if( $resp->is_error ) {
        die "Failed to wipeout $self->{name}, got error: " . $resp->status_line;
    }
    return 1;
}

sub logCursor {
    my ( $self ) = @_;
    my $res = undef;
    return sub {
        if( !$res ) {
            $res = $self->ua->post(
                "$self->{lastBuild}->{url}/logText/progressiveText", { start => 0 }
            )
        }
        elsif( $res->header("X-More-Data") && $res->header("X-More-Data") eq 'true' ) {
            $res = $self->ua->post(
                "$self->{lastBuild}->{url}/logText/progressiveText", { 
                    start => $res->header("X-Text-Size")
                }
            );
        }
        else {
            # there was a previous response but X-More-Data not set, so we are done
            return undef;
        }
        return $res->decoded_content || "";
    }
}

sub disable {
    my ( $self ) = @_;
    $self->j->login();
    my $resp = $self->ua->post("$self->{url}/disable", {});
    if( $resp->is_error ) {
        die "Failed to disable $self->{name}, got error: " . $resp->status_line;
    }
    return 1;
}

sub enable {
    my ( $self ) = @_;
    $self->j->login();
    my $resp = $self->ua->post("$self->{url}/enable", {});
    if( $resp->is_error ) {
        die "Failed to enable $self->{name}, got error: " . $resp->status_line;
    }
    return 1;
}


1;
