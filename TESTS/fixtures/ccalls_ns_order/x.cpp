// `b::f` written inside `namespace a`: `a::b` is not declared in this file, the global `b::f` is the one.
namespace b {
int f() { return 1; }
}

namespace a {
void g() { b::f(); }
}
