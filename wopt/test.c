#include "wopt.h"

int main(void) {
    Wopt_Module m = wopt_module_new();
    wopt_module_free(m);
}
