#include "cfg.hpp"

namespace cfg {
int mutate(int x) {
    return x + 1;
}

namespace inner {
int deep(int x) {
    return x * 2;
}
}
}
