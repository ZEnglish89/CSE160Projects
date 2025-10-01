#include <Timer.h>
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
}

implementation{
    uint16_t currentSequence = 0;

    // Get next sequence number for floods we initiate
    uint16_t getSequence() {
        currentSequence++;
        return currentSequence;
    }
    //setting ourselves up, with a sequence of 0.
    command void Flooding.initializeFlooding(){
        currentSequence = 0;
        dbg(FLOODING_CHANNEL,"Flooding initialized for node %d\n", TOS_NODE_ID);
    }

    command void Flooding.startFlood(uint16_t dest_addr, uint8_t *pld, uint8_t pld_len){
        //initializing some empty variables for later
        uint16_t sequenceNumber;
        pack floodMsg;
        uint8_t totalPayloadSize;
        //Because I want to avoid an entire new header, we're just packing in one value: the original sender.
        //That should be the only thing we need that isn't tracked by the original packet header.
        nx_uint16_t originalSrc;
        
        //new sequence number babyyyy
        sequenceNumber = getSequence();
        
        //announce who we are and what we're starting
        if(dest_addr == 0) {
            dbg(FLOODING_CHANNEL,"Node %d starting BROADCAST flood with seq %d\n", TOS_NODE_ID, sequenceNumber);
        } else {
            dbg(FLOODING_CHANNEL,"Node %d starting TARGETED flood to node %d with seq %d\n", TOS_NODE_ID, dest_addr, sequenceNumber);
        }
        
        // Create flooding header
        floodMsg.src = TOS_NODE_ID;
        originalSrc = TOS_NODE_ID;
        floodMsg.dest = dest_addr;
        floodMsg.seq = sequenceNumber;
        floodMsg.TTL = MAX_TTL;
        
        // Calculate available payload size(the maximum size minus the size of the originalSrc field).
        totalPayloadSize = pld_len + sizeof(nx_uint16_t);
        if(totalPayloadSize > PACKET_MAX_PAYLOAD_SIZE){
            pld_len = PACKET_MAX_PAYLOAD_SIZE - sizeof(nx_uint16_t);
            totalPayloadSize = PACKET_MAX_PAYLOAD_SIZE;
        }        


        //we entertained making a new protocal to have flooding operate more independently, but the assignment documents
        //say that we should be using pings and pingreplies, it works out pretty well: floods are pings, ACKs are pingreplies.
        floodMsg.protocol = PROTOCOL_PING;
        
        // Copy original source to payload
        memcpy(floodMsg.payload, &originalSrc, sizeof(nx_uint16_t));
        
        // Copy payload after the source
        memcpy(floodMsg.payload + sizeof(nx_uint16_t), pld, pld_len);
        
        // Send initial flood via broadcast. No need to send it more intelligently, because it's the first instance of the flood
        // and we just want it to go everywhere.
        call SimpleSend.send(floodMsg, AM_BROADCAST_ADDR);
        
        if(dest_addr == 0) {
            dbg(FLOODING_CHANNEL,"Node %d initiated BROADCAST flood seq %d\n", TOS_NODE_ID, sequenceNumber);
        } else {
            dbg(FLOODING_CHANNEL,"Node %d initiated TARGETED flood seq %d to node %d\n", TOS_NODE_ID, sequenceNumber, dest_addr);
        }
    }
}