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
   uses interface NeighborDiscovery;
   uses interface LinkState;
}

implementation{
   void forwardFloodToNeighbors(pack* floodPkt, uint16_t senderId);
   bool isDuplicateFlood(uint16_t floodSource, uint16_t seqNum);
   void sendFloodAck(uint16_t dest_node, uint16_t seq_num);

   uint16_t currentSequence = 0;
   FloodCacheEntry floodCache[MAX_FLOOD_CACHE_ENTRIES];
   uint8_t floodCacheSize = 0;

   uint16_t getSequence() {
      currentSequence++;
      return currentSequence;
   }

   command void Flooding.initializeFlooding(){
      currentSequence = 0;
   }

   command void Flooding.startFlood(uint16_t dest_addr, uint8_t *pld, uint8_t pld_len, nx_uint8_t protocol){
      uint16_t sequenceNumber;
      pack floodMsg;
      FloodHeader fh;
      uint8_t totalPayloadSize;
      
      sequenceNumber = getSequence();
      
      fh.floodSrc = TOS_NODE_ID;
      fh.floodDest = dest_addr;
      fh.floodSeq = sequenceNumber;
      fh.floodTTL = MAX_TTL;
      fh.floodType = FLOOD_TYPE_DATA;
      
      totalPayloadSize = FLOOD_HEADER_SIZE + pld_len;
      if(totalPayloadSize > PACKET_MAX_PAYLOAD_SIZE) {
            pld_len = PACKET_MAX_PAYLOAD_SIZE - FLOOD_HEADER_SIZE;
      }
      
      floodMsg.src = TOS_NODE_ID;
      floodMsg.dest = AM_BROADCAST_ADDR;
      floodMsg.seq = 0;
      floodMsg.TTL = MAX_TTL;
      floodMsg.protocol = protocol;
      
      memcpy(floodMsg.payload, &fh, FLOOD_HEADER_SIZE);
      memcpy(floodMsg.payload + FLOOD_HEADER_SIZE, pld, pld_len);
      
      call SimpleSend.send(floodMsg, AM_BROADCAST_ADDR);
   }

   command void Flooding.handleFloodPacket(pack* receivedPkt, uint8_t pktLen, uint16_t senderId) {
      FloodHeader fh;
      uint8_t appPayloadLength;
      uint8_t appPayloadBuffer[PACKET_MAX_PAYLOAD_SIZE - FLOOD_HEADER_SIZE];
      
      memcpy(&fh, receivedPkt->payload, FLOOD_HEADER_SIZE);
      
      if(isDuplicateFlood(fh.floodSrc, fh.floodSeq)) {
            return;
      }
      
      if(fh.floodTTL == 0) {
            return;
      }

      if(fh.floodType == FLOOD_TYPE_ACK) {
            if(fh.floodDest == TOS_NODE_ID) {
               signal Flooding.floodAckReceived(fh.floodSrc, fh.floodSeq);
               return;
            }
            
            fh.floodTTL--;
            memcpy(receivedPkt->payload, &fh, FLOOD_HEADER_SIZE);
            forwardFloodToNeighbors(receivedPkt, senderId);
            return;
      }
      
      if(receivedPkt->protocol == PROTOCOL_LINKSTATE) {
            appPayloadLength = pktLen - FLOOD_HEADER_SIZE;
            if(appPayloadLength > sizeof(appPayloadBuffer)) {
                appPayloadLength = sizeof(appPayloadBuffer);
            }
            
            memcpy(appPayloadBuffer, &receivedPkt->payload[FLOOD_HEADER_SIZE], appPayloadLength);
            call LinkState.handleRoutingPacket(appPayloadBuffer, appPayloadLength);
            
            fh.floodTTL--;
            memcpy(receivedPkt->payload, &fh, FLOOD_HEADER_SIZE);
            forwardFloodToNeighbors(receivedPkt, senderId);
            return;
      }
      
      if(fh.floodDest != 0 && fh.floodDest != TOS_NODE_ID) {
            // Forward targeted flood (not for us)
      } else {
            appPayloadLength = PACKET_MAX_PAYLOAD_SIZE - FLOOD_HEADER_SIZE;
            memcpy(appPayloadBuffer, &receivedPkt->payload[FLOOD_HEADER_SIZE], appPayloadLength);

            signal Flooding.floodReceived(fh.floodSrc, fh.floodSeq, 
                                        (uint8_t*)&(receivedPkt->payload[FLOOD_HEADER_SIZE]), 
                                        appPayloadLength);

            if(fh.floodDest != 0 && fh.floodDest == TOS_NODE_ID) {
               sendFloodAck(fh.floodSrc, fh.floodSeq);
               return;
            }
      }
      
      fh.floodTTL--;
      memcpy(receivedPkt->payload, &fh, FLOOD_HEADER_SIZE);
      forwardFloodToNeighbors(receivedPkt, senderId);
   }

   void forwardFloodToNeighbors(pack* floodPkt, uint16_t senderId) {
      uint8_t i;
      uint8_t neighborCount;
      uint16_t neighborId;
      bool forwarded = FALSE;
      FloodHeader fh;
      
      memcpy(&fh, floodPkt->payload, FLOOD_HEADER_SIZE);
      floodPkt->src = TOS_NODE_ID;
      
      neighborCount = call NeighborDiscovery.getNeighborCount();
      
      for(i = 0; i < neighborCount; i++) {
            neighborId = call NeighborDiscovery.getNeighbor(i);
            if(neighborId != senderId && neighborId != TOS_NODE_ID && neighborId != 0) {
               call SimpleSend.send(*floodPkt, neighborId);
               forwarded = TRUE;
            }
      }
   }

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
      
      if(floodCacheSize < MAX_FLOOD_CACHE_ENTRIES) {
            floodCache[floodCacheSize].nodeId = floodSource;
            floodCache[floodCacheSize].maxSeq = seqNum;
            floodCacheSize++;
      }
      return FALSE;
   }

   void sendFloodAck(uint16_t dest_node, uint16_t seq_num) {
      pack ackMsg;
      FloodHeader fh;
      
      fh.floodSrc = TOS_NODE_ID;
      fh.floodDest = dest_node;
      fh.floodSeq = seq_num;
      fh.floodTTL = MAX_TTL;
      fh.floodType = FLOOD_TYPE_ACK;
      
      ackMsg.src = TOS_NODE_ID;
      ackMsg.dest = AM_BROADCAST_ADDR;
      ackMsg.seq = 0;
      ackMsg.TTL = MAX_TTL;
      ackMsg.protocol = PROTOCOL_PINGREPLY;
      
      memcpy(ackMsg.payload, &fh, FLOOD_HEADER_SIZE);
      forwardFloodToNeighbors(&ackMsg, TOS_NODE_ID);
   }

   event void NeighborDiscovery.neighborsChanged(uint8_t neighborCount){
   }
}