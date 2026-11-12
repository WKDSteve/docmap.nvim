#include "util.h"

static int local(int n) {
    return n;
}

int run(void) {
    return twice(2) + local(1);
}
