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
    //We need neighbordiscovery to forward to neighbors
    uses interface NeighborDiscovery;

   //we need to send specific packets to the LinkState code.
    uses interface LinkState;
}

implementation{

//    void handleFloodPacket(pack* receivedPkt, uint8_t pktLen, uint16_t senderId);
    void forwardFloodToNeighbors(pack* floodPkt, uint16_t senderId);
    bool isDuplicateFlood(uint16_t floodSource, uint16_t seqNum);
    void sendFloodAck(uint16_t dest_node, uint16_t seq_num);

    uint16_t currentSequence = 0;

   FloodCacheEntry floodCache[MAX_FLOOD_CACHE_ENTRIES];
   uint8_t floodCacheSize = 0;

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

    command void Flooding.startFlood(uint16_t dest_addr, uint8_t *pld, uint8_t pld_len, nx_uint8_t protocol){
        //initializing some empty variables for later
         uint16_t sequenceNumber;
         pack floodMsg;
         FloodHeader fh;
         uint8_t totalPayloadSize;
         
         //new sequence number babyyyy
         sequenceNumber = getSequence();
         
         //announce who we are and what we're starting
         if(dest_addr == 0) {
            dbg(FLOODING_CHANNEL,"Node %d starting BROADCAST flood with seq %d\n", TOS_NODE_ID, sequenceNumber);
         } else {
            dbg(FLOODING_CHANNEL,"Node %d starting TARGETED flood to node %d with seq %d\n", TOS_NODE_ID, dest_addr, sequenceNumber);
         }
         
         // ADD THIS DEBUG LINE HERE:
         dbg(FLOODING_CHANNEL, "Node %d: Flooding - payload_len=%d, protocol=%d\n", 
            TOS_NODE_ID, pld_len, protocol);
         
         // Create flooding header
         fh.floodSrc = TOS_NODE_ID;
         fh.floodDest = dest_addr;
         fh.floodSeq = sequenceNumber;
         fh.floodTTL = MAX_TTL;
         fh.floodType = FLOOD_TYPE_DATA;
        
        // Calculate available space for application payload
        totalPayloadSize = FLOOD_HEADER_SIZE + pld_len;
        if(totalPayloadSize > PACKET_MAX_PAYLOAD_SIZE) {
            //if there's no space, reduce the payload down to the maximum. It's not exactly as fancy as IP fragmenting I admit, but anything more elegant is out of scope for this project.
            pld_len = PACKET_MAX_PAYLOAD_SIZE - FLOOD_HEADER_SIZE;
        }
        
        // Create packet
        floodMsg.src = TOS_NODE_ID;
        floodMsg.dest = AM_BROADCAST_ADDR;
        floodMsg.seq = 0;//These are filler values because our code is actually using the ones contained within the flooding header.
        floodMsg.TTL = MAX_TTL;
        //we entertained making a new protocal to have flooding operate more independently, but the assignment documents
        //say that we should be using pings and pingreplies.
        floodMsg.protocol = protocol;
        
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

    command void Flooding.handleFloodPacket(pack* receivedPkt, uint8_t pktLen, uint16_t senderId) {
      FloodHeader fh;
      uint8_t appPayloadLength;
      uint8_t appPayloadBuffer[PACKET_MAX_PAYLOAD_SIZE - FLOOD_HEADER_SIZE];
      uint8_t k;
      
      // Copy the flooding header from the packet payload
      memcpy(&fh, receivedPkt->payload, FLOOD_HEADER_SIZE);
      
      dbg(FLOODING_CHANNEL,"Node %d received flood type %d from src %d dest %d seq %d TTL %d via node %d\n", 
          TOS_NODE_ID, fh.floodType, fh.floodSrc, fh.floodDest, fh.floodSeq, fh.floodTTL, senderId);
      
      //Now we have to check all the different reasons why we may want to drop it or treat it special: duplicates, dead TTL, if it's just an ACK, etc.
      // Check for duplicates
      if(isDuplicateFlood(fh.floodSrc, fh.floodSeq)) {
         dbg(FLOODING_CHANNEL,"Node %d dropping duplicate flood\n", TOS_NODE_ID);
         return;
      }
      
      // Check TTL
      if(fh.floodTTL == 0) {
         dbg(FLOODING_CHANNEL,"Node %d dropping flood - TTL expired\n", TOS_NODE_ID);
         return;
      }

      //it could be useful to check the TTL *and* see if it's an ACK or not simultaneously, so we can report what type of flood got dropped.
      //consider for future updates, I suppose.

      // Handle ACK floods
      if(fh.floodType == FLOOD_TYPE_ACK) {
         //If we're the destination, signal that we got it and move on.
         if(fh.floodDest == TOS_NODE_ID) {

            //having the Event for received floods is a pain for allowing things aside from Node to use this module,
            //so we can just make an announcement here.
            //dbg(FLOODING_CHANNEL,"Node %d received ACK for flood seq %d from node %d\n", TOS_NODE_ID, fh.floodSeq, fh.floodSrc);
            signal Flooding.floodAckReceived(fh.floodSrc, fh.floodSeq);
            //The ACK got to us, no reason to keep flooding it.
            return;
         }
         
         //Otherwise, forward it further. No need to check TTL because we did that above.
         // Decrement TTL and update the packet
         fh.floodTTL--;
         memcpy(receivedPkt->payload, &fh, FLOOD_HEADER_SIZE);
         
         //Forward the ACK to everyone except the node who sent it to us, to minimize looping.
         forwardFloodToNeighbors(receivedPkt, senderId);
         dbg(FLOODING_CHANNEL,"Node %d forwarding ACK flood seq %d\n", TOS_NODE_ID, fh.floodSeq);
         return;
      }
      
      // Handle regular/data floods, now that ACKs are out of the way.
      // Check if this flood is targeted(not a broadcast) and we're not the destination
      if(fh.floodDest != 0 && fh.floodDest != TOS_NODE_ID) {
         //If it's targeted but we aren't the destination, then we skip all the hard work and move ahead to forwarding it.
         dbg(FLOODING_CHANNEL,"Node %d forwarding targeted flood (not for us)\n", TOS_NODE_ID);
      } else {
         // We are either the destination or it's a broadcast flood, so we have to actually deal with it.
         // Calculate application payload length
         appPayloadLength = PACKET_MAX_PAYLOAD_SIZE - FLOOD_HEADER_SIZE;
         
         // Copy application payload to buffer, ta-daa it's ours now.
         memcpy(appPayloadBuffer, &receivedPkt->payload[FLOOD_HEADER_SIZE], appPayloadLength);

         //if this is a LINKSTATE packet, we have additional work to do.
         if (receivedPkt->protocol == PROTOCOL_LINKSTATE){
            appPayloadLength = pktLen - FLOOD_HEADER_SIZE;
            
            // DEBUG: Print the actual payload bytes (FIX THE FORMATTING)
            dbg(FLOODING_CHANNEL, "Node %d: LSA payload length=%d, bytes: ", TOS_NODE_ID, appPayloadLength);
            for(k = 0; k < appPayloadLength && k < 16; k++) {
               dbg(FLOODING_CHANNEL, "%02x ", receivedPkt->payload[FLOOD_HEADER_SIZE + k]);
            }
            dbg(FLOODING_CHANNEL, "\n");
            
            call LinkState.handleRoutingPacket(&receivedPkt->payload[FLOOD_HEADER_SIZE], appPayloadLength);
         }
         
         // Signal application that we received a flood
         //same as above, it's better/easier to announce here rather than leaning on another Event.
         signal Flooding.floodReceived(fh.floodSrc, fh.floodSeq, appPayloadBuffer, appPayloadLength);
//         dbg(GENERAL_CHANNEL, "Node %d: Received flood from node %d, seq %d, payload: %.*s\n", 
//            TOS_NODE_ID, fh.floodSrc, fh.floodSeq, appPayloadBuffer,appPayloadLength);
  
         // If this is a targeted flood and we're the destination, send an ACK in return.
         if(fh.floodDest != 0 && fh.floodDest == TOS_NODE_ID) {
            dbg(FLOODING_CHANNEL,"Node %d is destination for targeted flood seq %d, sending ACK\n", 
                TOS_NODE_ID, fh.floodSeq);
            // Send ACK back to source
            sendFloodAck(fh.floodSrc, fh.floodSeq);
            // The flood has already reached us, so there's no reason to keep forwarding.
            return;
         }
      }
      
      // Decrement TTL and get ready to forward.
      fh.floodTTL--;
      memcpy(receivedPkt->payload, &fh, FLOOD_HEADER_SIZE);
      
      // Forward to everyone except who sent it to us, just like above.
      forwardFloodToNeighbors(receivedPkt, senderId);
   }

   // Forward a flood packet to all the node's neighbors except the one they received it from.
   void forwardFloodToNeighbors(pack* floodPkt, uint16_t senderId) {
      uint8_t i;
      uint8_t neighborCount;
      uint16_t neighborId;
      bool forwarded = FALSE;
      FloodHeader fh;
      
      // Copy flooding header to read sequence number
      memcpy(&fh, floodPkt->payload, FLOOD_HEADER_SIZE);
      
      // Update source to be us for the forwarded packets
      floodPkt->src = TOS_NODE_ID;
      
      // Get neighbor count from NeighborDiscovery
      neighborCount = call NeighborDiscovery.getNeighborCount();
      
      // Send to each neighbor except the sender
      for(i = 0; i < neighborCount; i++) {
         neighborId = call NeighborDiscovery.getNeighbor(i);
         //If the neighbor being considered isn't the sender, isn't ourselves, and isn't a broadcast ID
         if(neighborId != senderId && neighborId != TOS_NODE_ID && neighborId != 0) {
            dbg(FLOODING_CHANNEL,"Node %d forwarding flood seq %d to neighbor %d\n", 
                TOS_NODE_ID, fh.floodSeq, neighborId);
            //Then send that bad boy!
            call SimpleSend.send(*floodPkt, neighborId);
            forwarded = TRUE;
         }
      }
      //If we check all of our neighbors and there's nobody to forward it to, then say so and move on.
      if(!forwarded) {
         dbg(FLOODING_CHANNEL,"Node %d has no other neighbors to forward flood seq %d\n", 
             TOS_NODE_ID, fh.floodSeq);
      }
   }

   // Check if we've seen this flood before
   bool isDuplicateFlood(uint16_t floodSource, uint16_t seqNum) {
      uint8_t i;
      for(i = 0; i < floodCacheSize; i++) {
         //if the flood came from the node we're currently considering.
         if(floodCache[i].nodeId == floodSource) {
            //if we've already seen a sequence number that high or higher from that node, then it's a duplicate.
            if(floodCache[i].maxSeq >= seqNum) {
               return TRUE;
            }
            //if not, it must be new, so we can adjust our max and move on.
            floodCache[i].maxSeq = seqNum;
            return FALSE;
         }
      }
      
      //if we made it all the way through that loop without returning, this must come from a new source, so we can try adding it to the cache.
      if(floodCacheSize < MAX_FLOOD_CACHE_ENTRIES) {
         floodCache[floodCacheSize].nodeId = floodSource;
         floodCache[floodCacheSize].maxSeq = seqNum;
         floodCacheSize++;
      }
      //and if so, it can't possibly be a duplicate.
      return FALSE;
   }


      // Send ACK flood
   void sendFloodAck(uint16_t dest_node, uint16_t seq_num) {
      pack ackMsg;
      FloodHeader fh;
      
      dbg(FLOODING_CHANNEL,"Node %d sending ACK for seq %d to node %d\n", 
          TOS_NODE_ID, seq_num, dest_node);
      
      // Create ACK flooding header
      fh.floodSrc = TOS_NODE_ID;
      fh.floodDest = dest_node;
      fh.floodSeq = seq_num;
      fh.floodTTL = MAX_TTL;
      fh.floodType = FLOOD_TYPE_ACK;
      
      // Create ACK packet
      ackMsg.src = TOS_NODE_ID;
      ackMsg.dest = AM_BROADCAST_ADDR;
      ackMsg.seq = 0;
      ackMsg.TTL = MAX_TTL;
      //I don't think it actually makes a material difference if this is a ping or a pingreply, but it's thematically accurate.
      ackMsg.protocol = PROTOCOL_PINGREPLY;
      
      // Copy flooding header to payload
      memcpy(ackMsg.payload, &fh, FLOOD_HEADER_SIZE);
      
      // Send ACK flood via broadcast to start the flood. no need to be more intelligent about who we send to, it's a new flood.
      forwardFloodToNeighbors(&ackMsg, TOS_NODE_ID);
      dbg(FLOODING_CHANNEL,"Node %d sent ACK flood for seq %d\n", TOS_NODE_ID, seq_num);
   }
/*
   event void Flooding.floodReceived(uint16_t floodSource, uint16_t seqNum, uint8_t *payld, uint8_t payldLen) {
      dbg(GENERAL_CHANNEL, "Node %d: Received flood from node %d, seq %d, payload: %.*s\n", 
          TOS_NODE_ID, floodSource, seqNum, payldLen, payld);
   }

   event void Flooding.floodAckReceived(uint16_t source, uint16_t seq) {
      dbg(GENERAL_CHANNEL, "Node %d: Received ACK from node %d for flood seq %d\n", 
         TOS_NODE_ID, source, seq);
   }
*/
}