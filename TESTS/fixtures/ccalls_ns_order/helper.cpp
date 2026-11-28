// A member declared in its class body: `app::Helper::run`, never the free function `app::run`.
namespace app {
struct Helper {
  static void run() {}
};
}
