//basing this one on SimpleSend
#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"

configuration IPC{
    provides interface IP;
}

implementation{
//we definitely need SimpleSend and LinkState, I don't think anything else is strictly necessary though.

    components IPP;
    IP = IPP.IP;

    components new SimpleSendC(AM_PACK);
    IPP.SimpleSend -> SimpleSendC;

    components LinkStateC;
    IPP.LinkState -> LinkStateC;

//I'm including Flooding so that if we receive a packet that should be broadcast,
//we can flood it.
    components FloodingC;
    IPP.Flooding -> FloodingC;
}