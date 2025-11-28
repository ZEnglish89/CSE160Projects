#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/IP.h"

module IPP{
    provides interface IP;

    uses interface SimpleSend;
    uses interface Flooding;
    uses interface LinkState;
}

implementation{
    command void IP.sendMessage(uint16_t destAddr, uint8_t *payld, nx_uint8_t protocol){
        pack msg;
        IPHeader head;
        uint8_t uncastedNextHop;
        uint16_t NextHop;
        uint8_t payldLen;
        
        // If this is meant to be broadcast, let Flooding handle it.
        if (destAddr == 0){
            call Flooding.startFlood(destAddr, payld, PACKET_MAX_PAYLOAD_SIZE, protocol);
            return;
        }

        // Get the next hop information
        uncastedNextHop = call LinkState.getNextHop(destAddr);

        // If no route found, drop packet
        if(uncastedNextHop == 0xFF){
            dbg(GENERAL_CHANNEL, "Node %d: No route to %d, dropping packet\n", TOS_NODE_ID, destAddr);
            return;
        }

        // Cast to match packet header requirements
        NextHop = (uint16_t) uncastedNextHop;

        // Populate the IP header
        head.IPSrc = TOS_NODE_ID;
        head.IPDest = destAddr;
        head.IPTTL = MAX_TTL;
        head.IPProtocol = protocol;

        // Copy IP header into packet payload
        memcpy(msg.payload, &head, IP_HEADER_SIZE);

        // Copy application payload after IP header
        payldLen = PACKET_MAX_PAYLOAD_SIZE - IP_HEADER_SIZE;
        memcpy(msg.payload + IP_HEADER_SIZE, payld, payldLen);

        // Set packet headers
        msg.src = TOS_NODE_ID;
        msg.dest = NextHop;
        msg.TTL = 0;
        msg.seq = 0;
        msg.protocol = protocol;

        dbg(GENERAL_CHANNEL, "Node %d: Sending IP packet to %d via next hop %d\n", 
            TOS_NODE_ID, destAddr, NextHop);

        // Send the packet
        call SimpleSend.send(msg, NextHop);
    }

    command void IP.handleMessage(pack* msg, uint8_t pktLen, uint16_t senderId){
        IPHeader head;
        uint8_t finalDest;
        uint8_t uncastedNextHop;
        uint16_t NextHop;
        uint8_t payldLen;  // ADD THIS DECLARATION
        //I learned the hard way that declaring variables in the middle of commands rather than the beginning is a one-way ticket to permanent syntax errors.

        // Check if this is a link state packet (PROTOCOL_LINKSTATE)
        if (msg->protocol == PROTOCOL_LINKSTATE) {
            call Flooding.handleFloodPacket(msg, pktLen, senderId);
            return;
        }

        // For non-LSA packets, continue with IP processing
        memcpy(&head, msg->payload, IP_HEADER_SIZE);

        finalDest = (uint8_t) head.IPDest;

        // Check if we're the destination.
        if(finalDest == TOS_NODE_ID){
            payldLen = pktLen - IP_HEADER_SIZE;  // CALCULATE PAYLOAD LENGTH
            dbg(GENERAL_CHANNEL, "Node %d: DELIVERED PACKET! Payload: %.*s\n", 
                TOS_NODE_ID, payldLen, &(msg->payload[IP_HEADER_SIZE]));
            return;
        }

        // If this was a broadcast, let Flooding handle it.
        if(finalDest == AM_BROADCAST_ADDR){
            call Flooding.handleFloodPacket(msg, pktLen, senderId);
            return;
        }

        // Check TTL
        if(head.IPTTL == 0){
            dbg(GENERAL_CHANNEL, "Node %d dropping packet due to TTL\n", TOS_NODE_ID);
            return;
        }

        // Get next hop information
        uncastedNextHop = call LinkState.getNextHop(finalDest);

        // If no route found, drop packet
        if(uncastedNextHop == 0xFF){
            dbg(GENERAL_CHANNEL, "Node %d dropped packet due to no route to %d\n", TOS_NODE_ID, finalDest);
            return;
        }

        // Cast to match packet header requirements
        //I'm not sure if we actually need to cast this or if the types handle themselves,
        //but it doesn't hurt.
        NextHop = (uint16_t) uncastedNextHop;

        // Decrement TTL
        head.IPTTL -= 1;

        // If TTL still valid, forward packet
        if(head.IPTTL > 0){
            memcpy(msg->payload, &head, IP_HEADER_SIZE);
            //pack up all the new information for the next hop, same as in sendMessage()
            msg->src = TOS_NODE_ID;
            msg->dest = NextHop;
            msg->TTL = 0;
            msg->seq = 0;
//            msg->protocol = head.protocol;//no longer need this line because we'll just be leaving the protocol as whatever it already was.

            dbg(GENERAL_CHANNEL, "Node %d: Forwarding packet to %d via %d (TTL: %d)\n", 
                TOS_NODE_ID, finalDest, NextHop, head.IPTTL);
            
            call SimpleSend.send(*msg, NextHop);
            return;
        }
    }

    event void Flooding.floodReceived(uint16_t floodSource, uint16_t seqNum, uint8_t *payld, uint8_t payldLen) {
    }

    event void Flooding.floodAckReceived(uint16_t source, uint16_t seq) {
    }
}