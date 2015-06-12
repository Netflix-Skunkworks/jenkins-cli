package WWW::Jenkins::Node;

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
use WWW::Jenkins;
use WWW::Jenkins::Job;

sub new {
    my $class = shift;
    my $self = bless { @_ }, $class;
    for my $required ( qw(name jenkins) ) {
        defined $self->{$required} || die "no $required parameter to WWW::Jenkins::Node->new()";
    }
    $self->{url} ||= $self->j->{baseuri} . "/computer/$self->{name}";

    $self->{color} = $self->{offline} ? "red" : "green";
    my $busy = 0;
    for my $exec ( @{$self->{executors}} ) {
        $busy++ unless $exec->{idle};
    }
    $self->{offline} = $self->{offline};
    $self->{temporarilyOffline} = $self->{temporarilyOffline};
    $self->{busy} = $busy;
    $self->{executors} = $self->{numExecutors};
    return $self;
}

sub name {
    return shift->{"name"};
}

sub is_running {
    return shift->{busy};
}

sub offline {
    return shift->{offline};
}

sub tempOffline {
    return shift->{temporarilyOffline};
}

sub toggleOffline {
    my $self = shift;
    my $resp = $self->ua->post("$self->{url}/toggleOffline", {offlineMessage => ""});
    if( $resp->is_error ) {
        die "Failed to toggleOffline $self->{name}, got error: " . $resp->status_line;
    }
    return 1;
}

sub remove {
    my $self = shift;
    my $resp = $self->ua->post("$self->{url}/doDelete", {});
    if( $resp->is_error ) {
        die "Failed to nodeDelete $self->{name}, got error: " . $resp->status_line;
    }
    return 1;
}

*copy = *WWW::Jenkins::Job::copy;
*j = *WWW::Jenkins::Job::j;
*ua = *WWW::Jenkins::Job::ua;
*color = *WWW::Jenkins::Job::color
