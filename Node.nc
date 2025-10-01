/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "../../includes/packet.h"
#include "../../includes/command.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"
#include "../../includes/flooding.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

   uses interface Flooding;

   uses interface NeighborDiscovery;
}

implementation{
   pack sendPackage;
   FloodCacheEntry floodCache[MAX_FLOOD_CACHE_ENTRIES];
   uint8_t floodCacheSize = 0;

   // Prototypes
   void makePack(pack *pkg, uint16_t srcAddr, uint16_t destAddr, uint16_t timeToLive, uint16_t prot, uint16_t seqNum, uint8_t *payld, uint8_t payldLen);
   void handleFloodPacket(pack* receivedPkt, uint8_t pktLen, uint16_t senderId);
   void forwardFloodToNeighbors(pack* floodPkt, uint16_t senderId);
   bool isDuplicateFlood(uint16_t floodSource, uint16_t seqNum);

   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         call NeighborDiscovery.findNeighbors();
         call Flooding.initializeFlooding();
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
      pack* myMsg;
      pack responseMsg;
      uint8_t responsePayload[14];
      
      if(len == sizeof(pack)) {
         myMsg = (pack*) payload;
         
         // Check if this is a neighbor discovery packet
         if(strncmp((char*)myMsg->payload, "NEIGHBOR_DISC", 13) == 0) {
               dbg(NEIGHBOR_CHANNEL, "Received neighbor discovery from node %d\n", myMsg->src);
               
               // If we're not the sender, add to our neighbor table and respond
               if(myMsg->src != TOS_NODE_ID) {
                  // Send response back
                  responseMsg.src = TOS_NODE_ID;
                  responseMsg.dest = myMsg->src;
                  responseMsg.TTL = 1;
                  responseMsg.protocol = 1;
                  
                  memcpy(responsePayload, "NEIGHBOR_RESP", 13);
                  responsePayload[13] = '\0';
                  memcpy(responseMsg.payload, responsePayload, 14);
                  
                  call Sender.send(responseMsg, myMsg->src);
                  dbg(NEIGHBOR_CHANNEL, "Sent neighbor response to node %d\n", myMsg->src);
                  
                  // Add the discoverer to our neighbor table
                  call NeighborDiscovery.neighborUpdate(myMsg->src);
               }
               return msg;
         }
         // Check if this is a neighbor discovery response
         else if(strncmp((char*)myMsg->payload, "NEIGHBOR_RESP", 13) == 0) {
               dbg(NEIGHBOR_CHANNEL, "Received neighbor response from node %d\n", myMsg->src);
               
               // Add the responder to our neighbor table
               if(myMsg->src != TOS_NODE_ID) {
                  call NeighborDiscovery.neighborUpdate(myMsg->src);
               }
               return msg;
         }
         // Check if this is a flooding packet
         else if(myMsg->protocol == FLOOD_PROTOCOL) {
               dbg(FLOODING_CHANNEL, "Node %d: Received flooding packet from node %d\n", TOS_NODE_ID, myMsg->src);
               handleFloodPacket(myMsg, len, myMsg->src);
               return msg;
         }
         
         // If we get here, it's not a special packet
         dbg(GENERAL_CHANNEL, "Packet Received\n");
         dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
         return msg;
      }
      
      dbg(GENERAL_CHANNEL, "Packet Received - Unknown Packet Type %d\n", len);
      return msg;
   }

   // Handle flooding packets with neighbor-based forwarding
      // Handle flooding packets with neighbor-based forwarding
      // Handle flooding packets with neighbor-based forwarding
   void handleFloodPacket(pack* receivedPkt, uint8_t pktLen, uint16_t senderId) {
      FloodHeader fh;
      uint8_t appPayload[PACKET_MAX_PAYLOAD_SIZE - FLOOD_HEADER_SIZE];
      
      // Copy the flooding header from the packet payload
      memcpy(&fh, receivedPkt->payload, FLOOD_HEADER_SIZE);
      
      dbg(FLOODING_CHANNEL,"Node %d received flood from src %d seq %d TTL %d via node %d\n", 
          TOS_NODE_ID, fh.floodSrc, fh.floodSeq, fh.floodTTL, senderId);
      
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
      
      // Copy application payload to a separate buffer
      memcpy(appPayload, receivedPkt->payload + FLOOD_HEADER_SIZE, 
             PACKET_MAX_PAYLOAD_SIZE - FLOOD_HEADER_SIZE);
      
      // Signal application that we received a flood
      signal Flooding.floodReceived(fh.floodSrc, fh.floodSeq, 
                                   appPayload, 
                                   PACKET_MAX_PAYLOAD_SIZE - FLOOD_HEADER_SIZE);
      
      // Decrement TTL and update packet
      fh.floodTTL--;
      memcpy(receivedPkt->payload, &fh, FLOOD_HEADER_SIZE);
      
      // Forward to all neighbors EXCEPT the one we received it from
      forwardFloodToNeighbors(receivedPkt, senderId);
   }

   // Forward flood packet to all neighbors except the sender
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
         if(neighborId != senderId && neighborId != TOS_NODE_ID && neighborId != 0) {
            dbg(FLOODING_CHANNEL,"Node %d forwarding flood seq %d to neighbor %d\n", 
                TOS_NODE_ID, fh.floodSeq, neighborId);
            
            call Sender.send(*floodPkt, neighborId);
            forwarded = TRUE;
         }
      }
      
      if(!forwarded) {
         dbg(FLOODING_CHANNEL,"Node %d has no other neighbors to forward flood seq %d\n", 
             TOS_NODE_ID, fh.floodSeq);
      }
   }

   // Check if we've seen this flood before
   bool isDuplicateFlood(uint16_t floodSource, uint16_t seqNum) {
      uint8_t i;
      for(i = 0; i < floodCacheSize; i++) {
         if(floodCache[i].nodeId == floodSource) {
            if(floodCache[i].maxSeq >= seqNum) {
               return TRUE;
            }
            floodCache[i].maxSeq = seqNum;
            return FALSE;
         }
      }
      
      // New source, add to cache if space
      if(floodCacheSize < MAX_FLOOD_CACHE_ENTRIES) {
         floodCache[floodCacheSize].nodeId = floodSource;
         floodCache[floodCacheSize].maxSeq = seqNum;
         floodCacheSize++;
      }
      return FALSE;
   }

   event void CommandHandler.ping(uint16_t destAddr, uint8_t *payld){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destAddr, 0, 0, 0, payld, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, destAddr);
   }

   event void CommandHandler.neighDisc(){
   }

   event void CommandHandler.printNeighbors(){
      dbg(GENERAL_CHANNEL, "Node %d: Received printNeighbors command\n", TOS_NODE_ID);
      call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.startFlood(uint16_t destAddr, uint8_t *payld, uint8_t payldLen){
      dbg(GENERAL_CHANNEL, "Node %d: Received flood command\n", TOS_NODE_ID);
      call Flooding.startFlood(destAddr, payld, payldLen);
   }

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   event void Flooding.floodReceived(uint16_t floodSource, uint16_t seqNum, uint8_t *payld, uint8_t payldLen) {
      dbg(GENERAL_CHANNEL, "Node %d: Received flood from node %d, seq %d, payload: %.*s\n", 
          TOS_NODE_ID, floodSource, seqNum, payldLen, payld);
   }

   void makePack(pack *pkg, uint16_t srcAddr, uint16_t destAddr, uint16_t timeToLive, uint16_t prot, uint16_t seqNum, uint8_t* payld, uint8_t payldLen){
      pkg->src = srcAddr;
      pkg->dest = destAddr;
      pkg->TTL = timeToLive;
      pkg->seq = seqNum;
      pkg->protocol = prot;
      memcpy(pkg->payload, payld, payldLen);
   }
}