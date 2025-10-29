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

    components NeighborDiscoveryC;
    FloodingP.NeighborDiscovery -> NeighborDiscoveryC;

    components LinkStateC;
    FloodingP.LinkState -> LinkStateC;
}