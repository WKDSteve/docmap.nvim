#include "shape.hpp"

int main_app() {
    double a = area(2);
    double b = area(2.5);
    return perimeter(1) + static_cast<int>(a + b);
}
