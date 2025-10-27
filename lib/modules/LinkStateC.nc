
//This file will start off effectively identical to FloodingC.nc, and we can make changes to it later as necessary
#include "../../includes/CommandMsg.h"
#include "../../includes/command.h"
#include "../../includes/channels.h"

configuration LinkStateC{
    provides interface LinkState;
}

implementation{
    components LinkStateP;
    LinkState = LinkStateP.LinkState;

    components new SimpleSendC(AM_PACK);
    LinkStateP.SimpleSend -> SimpleSendC;

    components new NeighborDiscoveryC(AM_PACK);
    LinkStateP.NeighborDiscovery -> NeighborDiscoveryC;
}