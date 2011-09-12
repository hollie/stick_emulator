#! /usr/bin/perl -w

# Plugwise stick emulator
#
# Test code to verify the correct behaviour of the 
# xpl-plugwise code
#
# L. Hollevoet

use strict;

use IO::Socket;
use Net::hostent;  
use Digest::CRC qw(crc);
use Data::Dumper;

my $server_port = 2500;

my $server = IO::Socket::INET->new( Proto     => 'tcp',
				     LocalPort => $server_port,
				     Listen    => SOMAXCONN,
				     Reuse     => 1);
my $client;
my $framecount=0;

# Try starting the server
die "can't setup server" unless $server;
print "[Server $0 accepting clients on port $server_port...]\n";

# Main program loop, only one client at a time
while ($client = $server->accept()) {
    # Autoflush to prevent buffering
    $client->autoflush(1);

    print "[< Accepted connection from client...]\n";

    while ( <$client>) {
        my $frame = $_;
        $frame =~ s/(\n|.)*\x05\x05\x03\x03//g; # Strip header
        $frame =~ s/(\r\n)$//; # Strip trailing CRLF
        print "RX< $frame\n";

        # Check if the CRC matches
        if (! (plugwise_crc( substr($frame, 0, -4)) eq substr($frame, -4, 4))) {
            print "Received invalid CRC in frame $frame\n";
            next;
        }
        
        if ($frame =~ /^000A/){
            # Respond on init request
            print $client plugwise_ack();
            print $client plugwise_respond("0011", "00ABCDEF000000100000BEABCDEF00000010BABE");
            next;
        }
        
        if ($frame =~ /^0017([[:xdigit:]]{16})([[:xdigit:]]{2})/) {
            # Switch on/off command
            print $client plugwise_ack();
            my $rescode = $2 eq "00" ? "00DE" : "00D8";
            sleep 1;
            print $client plugwise_respond("0000", $rescode . $1);
            if ($framecount % 5 == 0) {
                #send triple response for testing every 5 packets
                print $client plugwise_respond("0000", $rescode . $1);
		print $client plugwise_respond("0000", $rescode . $1);
            }

            next;
        }

        if ($frame =~ /^0018([[:xdigit:]]{16})([[:xdigit:]]{2})/) {
            # Role call
            print $client plugwise_ack();
            # Simulate that we only have a single circle connected to the circle+
            # For others reply with FFF..FF
            my $rescode = $2 eq "00" ? "000D6F0000B1B967" : "FFFFFFFFFFFFFFFF";
            print $client plugwise_respond("0019", $1 . $rescode . $2);
            next;
        }

        if ($frame =~ /^0026([[:xdigit:]]{16})/) {
            # Respond to calibration request
            print $client plugwise_ack();
            my $rescode = $1 . "3F78BD69" . "B6FF0876" . "3CA99962" . "00000000";
            print $client plugwise_respond("0027", $rescode);
            next;
        }

        print "Oops: unknown message $frame\n";

    }
    
    # Once here, the client disconnected
    print "[> Remote peer disconnected ]\n";
    
    # Close and cleanup
    close $client;
    
}

sub plugwise_crc
{
  sprintf ("%04X", crc($_[0], 16, 0, 0, 0, 0x1021, 0));
}

sub plugwise_respond
{
    my $response=shift();
    my $payload=shift();
    my $seqnr = sprintf("%04X", $framecount);
    
    my $res = $response . $seqnr . $payload;
    print "TX> $res\n";

    $res = "\x05\x05\x03\x03" . $res . plugwise_crc($res) . "\r\n";
    
    
}

sub plugwise_ack 
{
    $framecount++;
    plugwise_respond("0000", "00C1");
}
