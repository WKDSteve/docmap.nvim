// `app::run` is a free function from a header outside the tree; `app::Helper::run` is the member.
void call_free() { app::run(); }

void call_member() { app::Helper::run(); }
