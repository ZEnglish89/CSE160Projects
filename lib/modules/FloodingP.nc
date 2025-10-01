#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"
#include "../../includes/flooding.h"
#include "../../includes/packet.h"
#include "../../includes/sendInfo.h"

module FloodingP{
    provides interface Flooding;

    uses interface Queue<sendInfo*>;
    uses interface Pool<sendInfo>;

    uses interface SimpleSend;

    uses interface NeighborDiscovery;
}

implementation{

    uint16_t trackPackets[256];

    command void Flooding.initializeFlooding(){
        //This table will keep track of what sequence numbers have already been seen.
        //dbg(FLOODING_CHANNEL,"setting up Flooding table for node %d\n", TOS_NODE_ID);
        
        uint8_t i;
        
        for (i = 0; i < 256; i++){
            trackPackets[i] = 0;
        }
        dbg(FLOODING_CHANNEL,"Flooding table set up for node %d.\n", TOS_NODE_ID);
    }

    command void Flooding.startFlood(uint8_t dest,uint8_t *payload, uint8_t length){
        uint8_t sequenceNumber = getSequence();
//        dbg(FLOODING_CHANNEL,"Starting flooding with sequence number %d from Node %d.\n", sequenceNumber,TOS_NODE_ID);
        //Make the packet, I'm doing each value manually to make sure I don't lose track of anything.
        
        pack floodMsg;
        
        floodMsg.src = TOS_NODE_ID;//This node is the source.
        floodMsg.dest = dest;//The destination is passed in.
        floodMsg.seq = sequenceNumber;//Get a new sequence number for this flood.
        floodMsg.TTL = MAX_TTL; // Arbitrary TTL value for flooding, setting it to the max allowed in the header for now.
        //This will almost certainly result in packets living for longer than they need to, but for now it's a start.
        floodMsg.protocol = 0; // A ping is probably a good thing to set this to for now? It requests a response, after all.
        memcpy(floodMsg.payload,payload,length);//Payload is set from the arguement.

        //This should now give us a packet that is ready to send to commence the flooding process.
        //The first node involved in flooding can simply broadcast, as it did not receive the packet from anyone else
        //and does not need to avoid sending it "backwards."

        call SimpleSend.send(floodMsg,AM_BROADCAST_ADDR);

        dbg(FLOODING_CHANNEL,"Flooding packet number %d broadcasted from Node %d\n", sequenceNumber, TOS_NODE_ID);
    }
}