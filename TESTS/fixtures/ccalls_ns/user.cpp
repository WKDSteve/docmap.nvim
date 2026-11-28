#include "cfg.hpp"
#include "outline.hpp"

namespace cfg {
// Relative: inside namespace cfg, inner::deep is cfg::inner::deep.
int local_call(int x) {
    return inner::deep(x);
}
}

int use_all(int x) {
    return cfg::mutate(x) + ::cfg::inner::deep(x) + out::ol(x) + std::max(x, 1);
}
