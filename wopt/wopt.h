#ifndef WOPT_H
#define WOPT_H

typedef void *Wopt_Module;

Wopt_Module wopt_module_new(void);
void wopt_module_free(Wopt_Module module);

#endif // WOPT_H
