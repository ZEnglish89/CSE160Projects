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
    CMD_ERROR = 9

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

    def addChannel(self, channelName, out=sys.stdout):
        print 'Adding Channel', channelName;
        self.t.addChannel(channelName, out);

def main():
    s = TestSim();
    s.runTime(10);
    s.loadTopo("long_line.topo");
    s.loadNoise("no_noise.txt");
    s.bootAll();
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);
    s.addChannel(s.FLOODING_CHANNEL);
    #s.addChannel(s.NEIGHBOR_CHANNEL);

    # Let neighbor discovery run for a while
    s.runTime(120000)
    

    s.neighborDMP(5)    

    s.runTime(2000)

    s.flood(3,18,"Test1")

    s.runTime(2000)
    
    s.moteOff(5)

    s.runTime(20000)

    s.flood(4,7,"Test2")

    s.runTime(2000)

    s.neighborDMP(6)

    s.runTime(10000)  # Final wait

    
"""    # Then dump neighbor tables for all nodes
    print "=== DUMPING NEIGHBOR TABLES ==="
    for node_id in s.moteids:
        print "Requesting neighbor dump for node", node_id
        s.neighborDMP(node_id)
        s.runTime(1000);  # Small delay between commands
    
    s.runTime(10000);  # Give time for all print commands to execute

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
"""

if __name__ == '__main__':
    main()