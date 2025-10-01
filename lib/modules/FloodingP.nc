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

    command void Flooding.initializeFlooding(){
        currentSequence = 0;
        dbg(FLOODING_CHANNEL,"Flooding initialized for node %d\n", TOS_NODE_ID);
    }

    command void Flooding.startFlood(uint16_t dest_addr, uint8_t *pld, uint8_t pld_len){
        uint16_t sequenceNumber;
        pack floodMsg;
        FloodHeader fh;
        uint8_t totalPayloadSize;
        
        sequenceNumber = getSequence();
        
        if(dest_addr == 0) {
            dbg(FLOODING_CHANNEL,"Node %d starting BROADCAST flood with seq %d\n", TOS_NODE_ID, sequenceNumber);
        } else {
            dbg(FLOODING_CHANNEL,"Node %d starting TARGETED flood to node %d with seq %d\n", TOS_NODE_ID, dest_addr, sequenceNumber);
        }
        
        // Create flooding header
        fh.floodSrc = TOS_NODE_ID;
        fh.floodDest = dest_addr;
        fh.floodSeq = sequenceNumber;
        fh.floodTTL = MAX_TTL;
        fh.floodType = FLOOD_TYPE_DATA;
        
        // Calculate available space for application payload
        totalPayloadSize = FLOOD_HEADER_SIZE + pld_len;
        if(totalPayloadSize > PACKET_MAX_PAYLOAD_SIZE) {
            pld_len = PACKET_MAX_PAYLOAD_SIZE - FLOOD_HEADER_SIZE;
        }
        
        // Create packet
        floodMsg.src = TOS_NODE_ID;
        floodMsg.dest = AM_BROADCAST_ADDR;
        floodMsg.seq = 0;
        floodMsg.TTL = MAX_TTL;
        floodMsg.protocol = FLOOD_PROTOCOL;
        
        // Copy flooding header to payload
        memcpy(floodMsg.payload, &fh, FLOOD_HEADER_SIZE);
        
        // Copy application payload after flooding header
        memcpy(floodMsg.payload + FLOOD_HEADER_SIZE, pld, pld_len);
        
        // Send initial flood via broadcast
        call SimpleSend.send(floodMsg, AM_BROADCAST_ADDR);
        
        if(dest_addr == 0) {
            dbg(FLOODING_CHANNEL,"Node %d initiated BROADCAST flood seq %d\n", TOS_NODE_ID, sequenceNumber);
        } else {
            dbg(FLOODING_CHANNEL,"Node %d initiated TARGETED flood seq %d to node %d\n", TOS_NODE_ID, sequenceNumber, dest_addr);
        }
    }
}