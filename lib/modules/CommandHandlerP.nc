#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"

module CommandHandlerP{
   provides interface CommandHandler;
   uses interface Receive;
   uses interface Pool<message_t>;
   uses interface Queue<message_t*>;
   uses interface Packet;
}

implementation{
    task void processCommand(){
        if(! call Queue.empty()){
            CommandMsg *msg;
            uint8_t commandID;
            uint8_t* buff;
            message_t *raw_msg;
            void *payload;
            uint8_t payloadLength;

            // Pop message out of queue.
            raw_msg = call Queue.dequeue();
            payload = call Packet.getPayload(raw_msg, sizeof(CommandMsg));

            // Check to see if the packet is valid.
            if(!payload){
                call Pool.put(raw_msg);
                post processCommand();
                return;
            }
            // Change it to our type.
            msg = (CommandMsg*) payload;

            dbg(COMMAND_CHANNEL, "A Command has been Issued.\n");
            buff = (uint8_t*) msg->payload;
            commandID = msg->id;
            payloadLength = call Packet.payloadLength(raw_msg) - sizeof(CommandMsg) + sizeof(msg->payload);

            //Find out which command was called and call related command
            switch(commandID){
            case CMD_PING:
                dbg(COMMAND_CHANNEL, "Command Type: Ping\n");
                signal CommandHandler.ping(buff[0], &buff[1]);
                break;

            case CMD_NEIGHBOR_DISC:
                dbg(COMMAND_CHANNEL, "Command Type: Neighbor Discovery\n");
                signal CommandHandler.neighDisc();
                break;

            case CMD_NEIGHBOR_DUMP:
                dbg(COMMAND_CHANNEL, "Command Type: Neighbor Dump\n");
                signal CommandHandler.printNeighbors();
                break;

            case CMD_LINKSTATE_DUMP:
                dbg(COMMAND_CHANNEL, "Command Type: Link State Dump\n");
                signal CommandHandler.printLinkState();
                break;

            case CMD_ROUTETABLE_DUMP:
                dbg(COMMAND_CHANNEL, "Command Type: Route Table Dump\n");
                signal CommandHandler.printRouteTable();
                break;

            case CMD_FLOOD:
                dbg(COMMAND_CHANNEL, "Command Type: Flood\n");
                if(payloadLength > 1) {
                    signal CommandHandler.startFlood(buff[0], &buff[1], payloadLength-1);
                }
                break;

            case CMD_TEST_CLIENT:
                dbg(COMMAND_CHANNEL, "Command Type: Test Client\n");
                // Parse [dest],[srcPort],[destPort],[transfer]
                // Payload format: "dest,srcPort,destPort,transfer"
                if(payloadLength > 0) {
                    // For Project 3 demo, just trigger with hardcoded values
                    // In a complete implementation, parse the string
                    signal CommandHandler.setTestClient();
                }
                break;

            case CMD_TEST_SERVER:
                dbg(COMMAND_CHANNEL, "Command Type: Test Server\n");
                // Parse [address],[port]
                if(payloadLength > 0) {
                    // For Project 3 demo, just trigger with default port 123
                    signal CommandHandler.setTestServer();
                }
                break;

            case CMD_CLIENT_CLOSE:
                dbg(COMMAND_CHANNEL, "Command Type: Client Close\n");
                // Parse [client_addr],[dest],[srcPort],[destPort]
                if(payloadLength > 0) {
                    // For now, just close any active client
                    // In complete implementation, parse and close specific socket
                    // For demo, we'll just signal that we should close
                    signal CommandHandler.setAppClient(); // Reuse this event for demo
                }
                break;

            case CMD_KILL:
                dbg(COMMAND_CHANNEL, "Command Type: Kill\n");
                // Handle kill command if needed
                break;

            default:
                dbg(COMMAND_CHANNEL, "CMD_ERROR: \"%d\" does not match any known commands.\n", msg->id);
                break;
            }
            call Pool.put(raw_msg);
        }

        if(! call Queue.empty()){
            post processCommand();
        }
    }
    
    event message_t* Receive.receive(message_t* raw_msg, void* payload, uint8_t len){
        if (! call Pool.empty()){
            call Queue.enqueue(raw_msg);
            post processCommand();
            return call Pool.get();
        }
        return raw_msg;
    }
}