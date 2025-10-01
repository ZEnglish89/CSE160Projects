#ifndef FLOODING_H
#define FLOODING_H

#include "protocol.h"

uint8_t nextSequence = 0;
uint8_t sequenceMax = 255;

int getSequence(){
    uint8_t sequenceGiven = nextSequence;
    if (nextSequence == sequenceMax){
        nextSequence = 0;
    } else {
        nextSequence++;
    }
    return sequenceGiven;
}

#endif