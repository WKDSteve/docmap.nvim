#include "util.h"

int bump(int n) {
    return n + 1;
}

int twice(int n) {
    return bump(n) + bump(n);
}
