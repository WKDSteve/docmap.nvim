// Another `a::b::f`, in a file `x.cpp` does not include: never the target of its `b::f`.
namespace a {
namespace b {
int f() { return 2; }
}
}
