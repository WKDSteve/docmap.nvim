#include "shape.hpp"

double area(int side) {
    return side * side;
}

double area(double side) {
    return side * side;
}

int perimeter(int side) {
    return 4 * side;
}
