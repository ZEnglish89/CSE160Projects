#ANDES Lab - University of California, Merced
#Author: UCM ANDES Lab
#$Author: abeltran2 $
#$LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
#! /usr/bin/python
import sys
from TOSSIM import *
from CommandMsg import *

class TestSim:
    moteids=[]
    # COMMAND TYPES
    CMD_PING = 0
    CMD_NEIGHBOR_DISC = 1
    CMD_NEIGHBOR_DUMP = 2
    CMD_LINKSTATE_DUMP = 3
    CMD_ROUTETABLE_DUMP = 4
    CMD_TEST_CLIENT = 5
    CMD_TEST_SERVER = 6
    CMD_KILL = 7
    CMD_FLOOD = 8
    CMD_CLIENT_CLOSE = 9  
    

    # CHANNELS - see includes/channels.h
    COMMAND_CHANNEL="command";
    GENERAL_CHANNEL="general";

    # Project 1
    NEIGHBOR_CHANNEL="neighbor";
    FLOODING_CHANNEL="flooding";

    # Project 2
    ROUTING_CHANNEL="routing";

    # Project 3
    TRANSPORT_CHANNEL="transport";

    # Personal Debuggin Channels for some of the additional models implemented.
    HASHMAP_CHANNEL="hashmap";

    # Initialize Vars
    numMote=0

    def __init__(self):
        self.t = Tossim([])
        self.r = self.t.radio()

        #Create a Command Packet
        self.msg = CommandMsg()
        self.pkt = self.t.newPacket()
        self.pkt.setType(self.msg.get_amType())

    # Load a topo file and use it.
    def loadTopo(self, topoFile):
        print 'Creating Topo!'
        # Read topology file.
        topoFile = 'topo/'+topoFile
        f = open(topoFile, "r")
        self.numMote = int(f.readline());
        print 'Number of Motes', self.numMote
        for line in f:
            s = line.split()
            if s:
                print " ", s[0], " ", s[1], " ", s[2];
                self.r.add(int(s[0]), int(s[1]), float(s[2]))
                if not int(s[0]) in self.moteids:
                    self.moteids=self.moteids+[int(s[0])]
                if not int(s[1]) in self.moteids:
                    self.moteids=self.moteids+[int(s[1])]

    # Load a noise file and apply it.
    def loadNoise(self, noiseFile):
        if self.numMote == 0:
            print "Create a topo first"
            return;

        # Get and Create a Noise Model
        noiseFile = 'noise/'+noiseFile;
        noise = open(noiseFile, "r")
        for line in noise:
            str1 = line.strip()
            if str1:
                val = int(str1)
            for i in self.moteids:
                self.t.getNode(i).addNoiseTraceReading(val)

        for i in self.moteids:
            print "Creating noise model for ",i;
            self.t.getNode(i).createNoiseModel()

    def bootNode(self, nodeID):
        if self.numMote == 0:
            print "Create a topo first"
            return;
        self.t.getNode(nodeID).bootAtTime(1333*nodeID);

    def bootAll(self):
        i=0;
        for i in self.moteids:
            self.bootNode(i);

    def moteOff(self, nodeID):
        self.t.getNode(nodeID).turnOff();

    def moteOn(self, nodeID):
        self.t.getNode(nodeID).turnOn();

    def run(self, ticks):
        for i in range(ticks):
            self.t.runNextEvent()

    # Rough run time. tickPerSecond does not work.
    def runTime(self, amount):
        self.run(amount)

    # Generic Command
    def sendCMD(self, ID, dest, payloadStr):
        self.msg.set_dest(dest);
        self.msg.set_id(ID);
        self.msg.setString_payload(payloadStr)

        self.pkt.setData(self.msg.data)
        self.pkt.setDestination(dest)
        self.pkt.deliver(dest, self.t.time()+5)

    def ping(self, source, dest, msg):
        self.sendCMD(self.CMD_PING, source, "{0}{1}".format(chr(dest),msg));
    
#    def flood(self, source, msg):
#        payload = chr(0) + msg  # 0 means broadcast to all nodes
#        self.sendCMD(self.CMD_FLOOD, source, payload)
#better to have just one function for flooding, and we can pass in a 0 if we want a broadcast.
    def flood(self, source, destination, msg):
        # the first byte is the destination, the rest is the message
        payload = chr(destination) + msg
        self.sendCMD(self.CMD_FLOOD, source, payload)
    
    def neighborDISC(self, source):
        self.sendCMD(self.CMD_NEIGHBOR_DISC, source, "neighbor command")

    def neighborDMP(self, destination):
        self.sendCMD(self.CMD_NEIGHBOR_DUMP, destination, "neighbor command")

    def routeDMP(self, destination):
        self.sendCMD(self.CMD_ROUTETABLE_DUMP, destination, "routing command")

    def linkstateDMP(self, destination):
        self.sendCMD(self.CMD_LINKSTATE_DUMP, destination, "linkstate command")

    def addChannel(self, channelName, out=sys.stdout):
        print 'Adding Channel', channelName;
        self.t.addChannel(channelName, out);
    

    def testClient(self, client_node, server_node, src_port, dest_port, transfer_amount):
        """Start a TCP client that connects to a server"""
        # Send empty payload since Node.nc uses hardcoded values
        # Node.nc hardcodes: src_port=456, dest_port=123, server=1, transfer=100
        # We'll just send a dummy payload
        self.sendCMD(self.CMD_TEST_CLIENT, client_node, "client")

    def testServer(self, node_id, port):
        """Start a TCP server on a node"""
        # Send empty payload since Node.nc uses hardcoded values
        self.sendCMD(self.CMD_TEST_SERVER, node_id, "server")

    def testClientClose(self, client_node, server_node, src_port, dest_port):
        """Close a TCP client connection"""
        # Format: "client_addr,dest,srcPort,destPort"
        payload = "%d,%d,%d,%d" % (client_node, server_node, src_port, dest_port)
        self.sendCMD(self.CMD_CLIENT_CLOSE, client_node, payload)

    def timingTest(self):
        print "=== TIMING TEST ==="
        
        # Wait 3 minutes for neighbor discovery
        print "Waiting 3 minutes for neighbor discovery..."
        self.runTime(180000)
        
        # Print neighbor tables to confirm
        for node_id in self.moteids:
            self.neighborDMP(node_id)
            self.runTime(500)
        
        # Wait another minute for LSAs
        print "Waiting 1 minute for LSA exchange..."
        self.runTime(60000)
        
        # Check routing tables
        for node_id in self.moteids:
            self.routeDMP(node_id)
            self.runTime(500)

    def testLinkStateRouting(self):
        print "=== TESTING LINK STATE ROUTING ==="
        
        # Wait much longer for everything to stabilize
        print "Waiting for network stabilization (6 minutes)..."
        self.runTime(360000)  # 6 minutes
        
        print "=== NEIGHBOR TABLES ==="
        for node_id in self.moteids:
            self.neighborDMP(node_id)
            self.runTime(2000)
        
        # Wait for LSA propagation
        print "Waiting for LSA propagation (2 minutes)..."
        self.runTime(120000)
        
        print "=== ROUTING TABLES ==="
        for node_id in self.moteids:
            self.routeDMP(node_id)
            self.runTime(2000)
        
        print "=== LINK STATE DATABASES ==="
        for node_id in self.moteids:
            self.linkstateDMP(node_id)
            self.runTime(1000)
        
        # Test end-to-end routing
        print "\n=== TESTING END-TO-END ROUTING ==="
        if len(self.moteids) >= 19:
            source = 1
            dest = 7
            print "Node %d pinging node %d (should traverse erm hops)" % (source, dest)
            self.ping(source, dest, "END_TO_END_TEST")
            self.runTime(60000)
        else:
            source = 1
            dest = 8
            print "Node %d pinging node %d (should traverse some hops lol)" % (source, dest)
            self.ping(source, dest, "END_TO_END_TEST")
            self.runTime(60000)

        self.moteOff(4)
        self.runTime(12000)

        #print "=== ROUTING TABLES ==="
        #for node_id in self.moteids:
        #    self.routeDMP(node_id)
        #    self.runTime(2000)
        
        print "\n=== TESTING END-TO-END ROUTING ROUND TWO ==="
        if len(self.moteids) >= 19:
            source = 1
            dest = 6
            print "Node %d pinging node %d (should traverse erm hops)" % (source, dest)
            self.ping(source, dest, "END_TO_END_TEST")
            self.runTime(60000)
        else:
            source = 1
            dest = 8
            print "Node %d pinging node %d (should traverse some hops lol)" % (source, dest)
            self.ping(source, dest, "END_TO_END_TEST")
            self.runTime(60000)

        print "\n=== LINK STATE ROUTING TEST COMPLETE ==="

    def testSimplePing(self):
        print "=== SIMPLE PING TEST ==="
        print "Node 1 pinging Node 2 (direct neighbor)"
        self.ping(1, 2, "DIRECT_PING")
        self.runTime(10000)
        
        print "Node 1 pinging Node 3 (2 hops away)" 
        self.ping(1, 3, "TWO_HOP_PING")
        self.runTime(10000)
        
        print "Node 1 pinging Node 19 (18 hops away)"
        self.ping(1, 19, "LONG_PING")
        self.runTime(60000)


def main():
    s = TestSim();
    s.runTime(10);
    #s.loadTopo("example.topo");
    s.loadTopo("long_line.topo");

    s.loadNoise("no_noise.txt");
    s.bootAll();
#    s.addChannel(s.COMMAND_CHANNEL);
#    s.addChannel(s.GENERAL_CHANNEL);
#    s.addChannel(s.FLOODING_CHANNEL);
#    s.addChannel(s.ROUTING_CHANNEL);
#    s.addChannel(s.NEIGHBOR_CHANNEL);
    s.addChannel(s.TRANSPORT_CHANNEL);

    # Let neighbor discovery run for a while
    s.runTime(120000);  # 2 minutes to allow several discovery cycles
    
    print "=== STARTING TCP TEST ==="

    # Start server on node 1
    print "Starting TCP server on node 1, port 123"
    s.testServer(1, 123)
    s.runTime(5000)

    # Start client on node 2  
    print "Starting TCP client on node 2 connecting to node 1"
    s.testClient(2, 1, 456, 123, 100)  # These parameters are ignored
    s.runTime(5000)

    # Run for a while to see connection attempts
    print "Running TCP test for 30 seconds..."
    s.runTime(30000)
        
    print "=== TCP TEST COMPLETE ==="

    '''
    # Then dump neighbor tables for all nodes
    print "=== DUMPING NEIGHBOR TABLES ==="
    for node_id in s.moteids:
        print "Requesting neighbor dump for node", node_id
        s.neighborDMP(node_id)
        s.runTime(1000);  # Small delay between commands
    
    #s.runTime(10000);  # Give time for all print commands to execute

    print "=== STARTING FLOOD TEST ==="
    print "Node 1 broadcast flooding message: 'HELLO_FLOOD'"
    s.flood(1,0, "HELLO_FLOOD")
    
    # Let the flood propagate through the network
    s.runTime(100000);  # 10 seconds for flood propagation
    
    # Test 3: Start another flood from a different node
    print "Node 5 broadcast flooding message: 'SECOND_FLOOD'"
    s.flood(5,0, "SECOND_FLOOD")
    
    s.runTime(100000);  # 10 more seconds
    
    # Test 4: Verify flood reached all nodes by checking debug output
    print "=== FLOOD TEST COMPLETE ==="
    print "Check the output above for flood reception messages"

    # Test both broadcast and targeted flooding:
    print "=== Testing Targeted Flooding ==="
    print "Node 1 flooding targeted message to node 9"
    s.flood(1, 9, "TARGETED_TO_9")

    s.runTime(100000)  # Wait for flood and ACK
    
    # Dump neighbor tables again to see if anything changed, even though it definitely shouldn't.
    print "=== FINAL NEIGHBOR TABLES ==="
    for node_id in s.moteids:
        s.neighborDMP(node_id)
        s.runTime(500);
    
    

    print "=== STARTING LINK STATE ROUTING TEST ==="
    
    # Run the comprehensive test
    s.testLinkStateRouting()
    
    # Additional manual testing if needed
    print "\n=== ADDITIONAL MANUAL TESTING ==="
    
    # Keep the simulation running to see periodic LSAs
    print "Running for 2 more minutes to observe periodic updates..."
    s.runTime(120000)
    
    # Final state dump
    print "\n=== FINAL STATE ==="
    for node_id in s.moteids:
        print "Node %d Final Routing Table:" % node_id
        s.routeDMP(node_id)
        s.runTime(1000)
    
    print "=== TEST COMPLETE === "
    '''
    #print "=== STARTING COMPREHENSIVE LINK STATE ROUTING TEST ==="
    
    # Run the comprehensive test
    #s.testLinkStateRouting()
    #s.testSimplePing()
    # Keep running to see any final updates
    #print "Running for additional 30 seconds to observe final state..."
    #s.runTime(30000)
    
    #print "=== ALL TESTS COMPLETE ==="

if __name__ == '__main__':
    main()