package Hydra::Plugin::EventExporter;

use utf8;
use strict;
use parent 'Hydra::Plugin';

use POSIX qw(strftime);
use IO::Socket::UNIX;
use JSON;

=head1 Hydra Event Exporter Plugin

=cut

# block name to be used in the general hydra config file
my $CONFIG_SECTION = "event-exporter";

=head2 Subroutines

=cut

=over

=item _pluginConfig($main_config)

Parser of the plugin configuration block, 

  <event-exporter>
    enable = true
    debug = false
    socket = $ENV{HYDRA_DATA}/hydra.sock
    listen = build-queued
    listen = build-started
    listen = build-finished
    listen = step-finished
  </event-exporter>

=cut
sub _pluginConfig {
  my $main_config = shift @_;
  my $cfg = $main_config->{$CONFIG_SECTION};
  my $values = {
    socket => "$ENV{HYDRA_DATA}/hydra.sock",
    enable => 1,
    debug => 1,
    listen => {}
  };
  # verify if the user defined options in the config file
  foreach my $option ("socket", "enable", "debug") {
    if (defined $cfg->{socket}) {
      $values->{$option} = $cfg->{$option};
    }
  }
  # the listen option is different, it could be an array
  # or a single value, hence the special if block
  if ( defined $cfg->{listen} ) {
    if (ref($cfg->{listen}) eq "ARRAY") {
      foreach my $eventType ($cfg->{listen}) {
        # add all the keys in the Hash/set, the value is
        # set to undef becase we only care about the lookup
        $values->{listen}->{$eventType} = ();
      }
    } else {
      # add a single key in the Hash/set, the value is irrelevant
      $values->{listen}->{$cfg->{listen}} = ();
    }
  }
  return $values;
}

=item buildEventAsJSON($type, $content)

$type:
  Specifies the type of event, it should be one of:

   - build-queued
   - build-started
   - build-finished
   - step-finished

$content:
  Should be a JSON serializable structure.

Return a JSON encoded string with two top-level keys: "type" and "content" each
with the corresponding JSON encoded value of the argument that was passed.

=cut
sub buildEventAsJSON {
  my ($type, $content) = @_;
  my $event = {
     "type" => $type,
     "content" => $content
  };
  my $json = JSON->new;
  # to be able to use the TO_JSON method;
  $json->convert_blessed;
  return $json->encode($event);
}


=item getSocketClient($sock_path)

Takes no arguments and returns a new socket to which the events will be pushed.

=cut
sub getSocketClient {
  my $sock_path = shift @_;
  my $sock = IO::Socket::UNIX->new(
      Type => SOCK_STREAM(),
      Peer => $sock_path
  );
  $sock or die "Can't connect to socket at $sock_path";
  return $sock;
}


=back

=head2 Constructor

=over

=item new($class, %args)

Define special constructor to add the "myConfig" attribute
with the pre-parsed config values for the plugin.

=cut
sub new {
  my ($class, %args) = @_;
  my $self = {
    db => $args{db},
    config => $args{config},
    plugins => $args{plugins},
    myConfig => _pluginConfig($args{config})
  };
  bless $self, $class;
  if ($self->{myConfig}->{enable}){
    $self->_printDebug("Plugin enabled");
    return $self;
  } else {
    return undef;
  }

}

=back

=head2 Methods

=cut

=over

=item _printDebug($self, $msg)

Conditionally print the string $msg into STDERR
depending on the 'debug' config option for the plugin

=cut
sub _printDebug {
  my ($self, $msg) = @_;
  if($self->{myConfig}->{debug}) {
    my $current_time = strftime("%Y-%m-%d-%H:%M:%S", localtime);
    print( STDERR "[$current_time]:EventExporter: $msg\n" );
  }
}

=item _writeEvent($self, $type, $content)

=cut
sub _writeEvent {
  my ($self, $type, $content) = @_;
  if( exists $self->{myConfig}->{listen}->{$type} ){
    my $client = getSocketClient($self->{myconfig}->{socket});
    print($client buildEventAsJSON($type, $content));
    print($client "\n");
  } else {
    $self->_printDebug("listening for type $type is not enabled. Skipping.");
  }
}

=item buildFinished($self, $build, $dependents)

Event Handler.

Called when build $build has finished.  If the build failed, then
$dependents is an array ref to a list of builds that have also
failed as a result (i.e. because they depend on $build or a failed
dependeny of $build).

=cut
sub buildFinished {
    my ($self, $build, $dependents) = @_;
    $self->_printDebug("build-finished event received");
    my $content = {"build" => $build, "dependents" => $dependents };
    $self->_writeEvent("build-finished", $content);
}


=item buildQueued($self, $build)

Event Handler.

Called when build $build has been queued.

=cut
sub buildQueued {
    my ($self, $build) = @_;
    my $type = "build-queued";
    $self->_printDebug("$type event received");
    $self->_writeEvent($type, $build);
}

=item buildStarted($self, $build)

Event Handler.

Handler of the build-started event, if listening for this event is enabled
on the configuration, it'll write a JSON encoded representation of the
$build into the configured unix socket.

=cut
sub buildStarted {
    my ($self, $build) = @_;
    $self->_printDebug("build-started event received");
    $self->_writeEvent("build-started", $build);
}


=item stepFinished($self, $step, $logPath)

Event Handler.

Called when step $step has finished. The build log is stored in the file
$logPath (bzip2-compressed).

The logPath may be empty if the derivation was obtained via a binary substitute.

=cut
sub stepFinished {
    my ($self, $step, $logPath) = @_;
    $self->_printDebug("step-finished event received");
    my $content = {"step" => $step, "logPath" => $logPath };
    $self->_writeEvent("step-finished", $content);
}



=back
=cut
1;
