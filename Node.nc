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

   uses interface LinkState;

   uses interface IP;
}

implementation{
   pack sendPackage;

   void makePack(pack *pkg, uint16_t srcAddr, uint16_t destAddr, uint16_t timeToLive, uint16_t prot, uint16_t seqNum, uint8_t *payld, uint8_t payldLen);

   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         call NeighborDiscovery.findNeighbors();
         call Flooding.initializeFlooding();
//         call LinkState.initializeRouting();
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

		//if this is either a Neighbordiscovery message or a Neighbordiscovery response
		if((strncmp((char*)myMsg->payload, "NEIGHBOR_DISC", 13) == 0)||(strncmp((char*)myMsg->payload, "NEIGHBOR_RESP", 13) == 0)){ 
			//if we're the sender, just completely ignore it and move on.
			//Note that removing this if statement doesn't seem to affect functionality, there's a chance
			//that the nodes aren't receiving their own packets regardless, but there's no downside to
			//leaving this here to catch edge cases.
			if(myMsg->src!=TOS_NODE_ID){
				//let the relevant module handle it.
				call NeighborDiscovery.handleNeighborPacket(myMsg,responseMsg,responsePayload);
			}
			return msg;
		}
      //otherwise, let the IP module handle it, and it can call Flooding if necessary from within itself.
      else{
         call IP.handleMessage(myMsg,len,myMsg->src);
         return msg;
      }
/*         // otherwise, this is a flooding packet. based on our current setup, if it's not used for neighbordiscovery it must be a flood.
         else{
               dbg(FLOODING_CHANNEL, "Node %d: Received flooding packet from node %d, handling\n", TOS_NODE_ID, myMsg->src);
               call Flooding.handleFloodPacket(myMsg, len, myMsg->src);
               return msg;
         }
*/         
      }
      //we shouldn't ever get here, but still.
      dbg(GENERAL_CHANNEL, "Packet Received - Unknown Packet Type %d\n", len);
      return msg;
   }

   event void CommandHandler.ping(uint16_t destAddr, uint8_t *payld){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      call IP.sendMessage(destAddr,payld);
//      makePack(&sendPackage, TOS_NODE_ID, destAddr, 0, 0, 0, payld, PACKET_MAX_PAYLOAD_SIZE);
//      call Sender.send(sendPackage, destAddr);
   }

   event void CommandHandler.neighDisc(){
   }

   event void CommandHandler.printNeighbors(){
      dbg(GENERAL_CHANNEL, "Node %d: Received printNeighbors command\n", TOS_NODE_ID);
      call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.startFlood(uint16_t destAddr, uint8_t *payld, uint8_t payldLen){
      dbg(GENERAL_CHANNEL, "Node %d: Received flood command\n", TOS_NODE_ID);
      call Flooding.startFlood(destAddr, payld, payldLen,PROTOCOL_PING);
   }

   event void CommandHandler.printRouteTable(){
      dbg(GENERAL_CHANNEL, "Node %d: Received printRouteTable command\n", TOS_NODE_ID);
      call LinkState.printRouteTable();
   }

   event void CommandHandler.printLinkState(){
      dbg(GENERAL_CHANNEL, "Node %d: Received printLinkState command\n", TOS_NODE_ID);
      call LinkState.printLinkState();
   }

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   event void Flooding.floodReceived(uint16_t floodSource, uint16_t seqNum, uint8_t *payld, uint8_t payldLen) {
//      dbg(GENERAL_CHANNEL, "Node %d: Received flood from node %d, seq %d, payload: %.*s\n", 
//          TOS_NODE_ID, floodSource, seqNum, payldLen, payld);
   }

   event void Flooding.floodAckReceived(uint16_t source, uint16_t seq) {
//      dbg(GENERAL_CHANNEL, "Node %d: Received ACK from node %d for flood seq %d\n", 
//         TOS_NODE_ID, source, seq);
   }

   //This does nothing, we just need to include it because all events must exist when their module is used.
   //This event is *actually* useful in LinkStateP.nc
   event void NeighborDiscovery.neighborsChanged(uint8_t neighborCount){}

   void makePack(pack *pkg, uint16_t srcAddr, uint16_t destAddr, uint16_t timeToLive, uint16_t prot, uint16_t seqNum, uint8_t* payld, uint8_t payldLen){
      pkg->src = srcAddr;
      pkg->dest = destAddr;
      pkg->TTL = timeToLive;
      pkg->seq = seqNum;
      pkg->protocol = prot;
      memcpy(pkg->payload, payld, payldLen);
   }
}