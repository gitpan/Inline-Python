#ifndef PY2PL_H
#define PY2PL_H

extern SV* Py2Pl (PyObject *obj);
extern PyObject *Pl2Py(SV* obj);
extern void croak_python_exception();

#endif

