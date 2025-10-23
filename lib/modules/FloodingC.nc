#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"

configuration FloodingC{
   provides interface Flooding;
}

implementation{
    components FloodingP;
    Flooding = FloodingP.Flooding;

    components new SimpleSendC(AM_PACK);
    FloodingP.SimpleSend -> SimpleSendC;

    components new NeighborDiscoveryC(AM_PACK);
    FloodingP.NeighborDiscovery -> NeighborDiscoveryC;
}