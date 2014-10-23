/* -*- C -*- */
#include "EXTERN.h" 
#include "perl.h"
#include "XSUB.h"

#include "Python.h"
#include "py2pl.h"
#include "util.h"

#ifdef EXPOSE_PERL
#include "perlmodule.h"
#endif

/* To save a little time, I check the calling context and don't convert
 * the arguments if I'm in void context, flatten lists in list context,
 * and return only one element in scalar context.
 * 
 * If this turns out to be a bad idea, it's easy enough to turn off.
 */
#define CHECK_CONTEXT

#ifdef CREATE_PYTHON
void do_pyinit() {
#ifdef EXPOSE_PERL
  PyObject *main_dict;
  PyObject *perl_obj;

  PyObject *dummy1 = PyString_FromString(""), 
           *dummy2 = PyString_FromString("main");
#endif
  /* sometimes Python needs to know about argc and argv to be happy */
  int _python_argc = 1;
  char *_python_argv[] = {
    "python",
  };

  Py_SetProgramName("python");
  Py_Initialize();
  PySys_SetArgv(_python_argc, _python_argv);  /* Tk needs this */

#ifdef EXPOSE_PERL
  /* create the perl module and add functions */
  initperl();

  /* now -- create the main 'perl' object and add it to the dictionary. */
  perl_obj = newPerlPkg_object(dummy1,dummy2);
  main_dict = PyModule_GetDict(PyImport_AddModule("__main__"));
  PyDict_SetItemString(main_dict, "perl", perl_obj);

  Py_DECREF(dummy1); 
  Py_DECREF(dummy2);
#endif
}
#endif

MODULE = Inline::Python   PACKAGE = Inline::Python

BOOT:
#ifdef CREATE_PYTHON
do_pyinit();
#endif

PROTOTYPES: DISABLE

void 
py_study_package(PYPKG="__main__")
     char*   PYPKG
 PREINIT:
  PyObject *mod;
  PyObject *dict;
  PyObject *keys;
  int len;
  int i;
  AV* functions = newAV();
  HV* classes = newHV();
 PPCODE:
  mod = PyImport_AddModule(PYPKG);
  dict = PyModule_GetDict(mod);
  keys = PyMapping_Keys(dict);
  len = PyObject_Length(dict);
  Printf(("py_study_package: dict length: %i\n", len));
  for (i=0; i<len; i++) {
    PyObject *key = PySequence_GetItem(keys,i);
    PyObject *val = PyObject_GetItem(dict,key);
    if (PyCallable_Check(val)) {
#ifdef I_PY_DEBUG
	printf("py_study_package: #%i (%s) callable\n", i, PyString_AsString(key));
	printf("val:\n\t");
	PyObject_Print(val, stdout, Py_PRINT_RAW);
	printf("\n");
	printf("object type check gives: %i\n", PyType_Check(val));
#endif
      if (PyFunction_Check(val)) {
        char *name = PyString_AsString(key);
        Printf(("Found a function: %s\n", name));
	av_push(functions, newSVpv(name,0));
      }
      /* elw: if we just could get it to go through here! */
      else if (PyType_Check(val) || PyClass_Check(val)) {
        char *name = PyString_AsString(key);
	PyObject *cls_dict = PyObject_GetAttrString(val,"__dict__");
	PyObject *cls_keys = PyMapping_Keys(cls_dict);
	int dict_len = PyObject_Length(cls_dict);
	int j;

	/* array of method names */
	AV* methods = newAV();
	AV* bases = newAV();

	Printf(("Found a class: %s\n", name));

	/* populate the array */
	for (j=0; j<dict_len; j++) {
	  PyObject *cls_key = PySequence_GetItem(cls_keys,j);
	  PyObject *cls_val = PyObject_GetItem(cls_dict,cls_key);
	  char *fname = PyString_AsString(cls_key);
	  if (PyFunction_Check(cls_val)) {
	    Printf(("Found a method of %s: %s\n", name, fname));
	    av_push(methods,newSVpv(fname,0));
	  }
	  else {
	    Printf(("not a method %s: %s\n", name, fname));
	  }
	}

	hv_store(classes,name,strlen(name),newRV_noinc((SV*)methods), 0);
      }
    }
  }
  /* return an expanded hash */
  XPUSHs(newSVpv("functions",0));
  XPUSHs(newRV_noinc((SV*)functions));
  XPUSHs(newSVpv("classes", 0));
  XPUSHs(newRV_noinc((SV*)classes));

SV *
py_eval(str, type=1)
	char *str
	int type
    PREINIT:
	PyObject *	main_module;
	PyObject *	globals;
	PyObject *	locals;
	PyObject *	py_result;
	int 		context;
    CODE:
	Printf(("py_eval: code: %s\n", str));
	/* doc:  if the module wasn't already loaded, you will get an empty
	* module object. */
	main_module = PyImport_AddModule("__main__");
	if(main_module == NULL) {
		croak("Error -- Import_AddModule of __main__ failed");
	}
	Printf(("py_eval: main_module=%p\n", main_module));
	globals = PyModule_GetDict(main_module);
	Printf(("py_eval: globals=%p\n", globals));
	locals = globals;
	context = (type == 0) ? Py_eval_input : 
		  (type == 1) ? Py_file_input : 
				Py_single_input;
	Printf(("py_eval: type=%i\n", type));
	Printf(("py_eval: context=%i\n", context));
	py_result = PyRun_String(str, context, globals, locals);
	if (!py_result) {
		PyErr_Print();
		croak("Error -- py_eval raised an exception");
		XSRETURN_EMPTY;
	}
	RETVAL = Py2Pl(py_result);
	Py_DECREF(py_result);
    OUTPUT:
	RETVAL

#undef  NUM_FIXED_ARGS
#define NUM_FIXED_ARGS 2

void
py_call_function(PYPKG, FNAME, ...)
     char*    PYPKG;
     char*    FNAME;
  PREINIT:
  int i;

  PyObject *mod       = PyImport_AddModule(PYPKG);
  PyObject *dict      = PyModule_GetDict(mod);
  PyObject *func      = PyMapping_GetItemString(dict,FNAME);
  PyObject *o         = NULL;
  PyObject *py_retval = NULL;
  PyObject *tuple     = NULL;

  SV* ret = NULL;

  PPCODE:

  Printf(("py_call_function\n"));
  Printf(("package: %s\n", PYPKG));
  Printf(("function: %s\n", FNAME));

  if (!PyCallable_Check(func)) {
    croak("'%s' is not a callable object", FNAME);
    XSRETURN_EMPTY;
  }

  Printf(("function '%s' is callable!\n", FNAME));
  
  tuple = PyTuple_New(items-NUM_FIXED_ARGS);
  
  for (i=NUM_FIXED_ARGS; i<items; i++) {
    o = Pl2Py(ST(i));
    if (o) {
      PyTuple_SetItem(tuple, i-NUM_FIXED_ARGS, o);
    }
  }
  Printf(("calling func\n"));
  py_retval = PyObject_CallObject(func, tuple);
  Printf(("received a response\n"));
  if (!py_retval || (PyErr_Occurred() != NULL)) {
    fprintf(stderr,"Error: Python error occurred:\n");
    PyErr_Print();
    Py_XDECREF(tuple);
    Py_XDECREF(func);
    croak("Error -- PyObject_CallObject(...) failed.\n");
    XSRETURN_EMPTY;
  }
  Printf(("no error\n"));
#ifdef CHECK_CONTEXT
  Printf(("GIMME_V=%i\n", GIMME_V));
  Printf(("GIMME=%i\n", GIMME));
  Printf(("G_VOID=%i\n", G_VOID));
  Printf(("G_ARRAY=%i\n", G_ARRAY));
  Printf(("G_SCALAR=%i\n", G_SCALAR));

  /* We can save a little time by checking our context */
  /* For whatever reason, GIMME_V always returns G_VOID when we get forwarded
   * from eval_python(). 
   */
  if (GIMME_V == G_VOID)
    XSRETURN_EMPTY;
#endif

  Printf(("calling Py2Pl\n"));
  ret = Py2Pl(py_retval);
  Py_DECREF(py_retval);
  
  if (
#ifdef CHECK_CONTEXT
      (GIMME_V == G_ARRAY) &&
#endif
      SvROK(ret) && (SvTYPE(SvRV(ret)) == SVt_PVAV)) {
    AV* av = (AV*)SvRV(ret);
    int len = av_len(av) + 1;
    int i;
    for (i=0; i<len; i++) {
      XPUSHs(sv_2mortal(av_shift(av)));
    }
  } else {
    XPUSHs(ret);
  }

#undef  NUM_FIXED_ARGS
#define NUM_FIXED_ARGS 2

void
py_call_method(_inst, mname, ...)
	SV*	_inst;
	char*	mname;
  PREINIT:

  PyObject *inst;
  PyObject *inherited_method = NULL;

  /* Other variables */
  PyObject *method;    /* the method object */
  PyObject *tuple;     /* the parameters */
  PyObject *py_retval; /* the return value */
  int i;
  SV *ret;

  PPCODE:

  Printf(("eval_python_method\n"));

  if (SvROK(_inst) && SvTYPE(SvRV(_inst))==SVt_PVMG) {
    inst = (PyObject*)SvIV(SvRV(_inst));
  }
  else {
    croak("Object did not have Inline::Python::Object magic");
    XSRETURN_EMPTY;
  }

  Printf(("inst {%p} successfully passed the PVMG test\n", inst));

  if (!(PyInstance_Check(inst) || inst->ob_type->tp_flags & Py_TPFLAGS_HEAPTYPE)) {
    croak("Attempted to call method '%s' on a non-instance", mname);
    XSRETURN_EMPTY;
  }

  Printf(("inst is indeed a Python Instance\n"));

  if (!PyObject_HasAttrString(inst, mname)) {
    croak("Python object has no method named %s", mname);
    XSRETURN_EMPTY;
  }

  Printf(("inst has an attribute named '%s'\n", mname));

  method = PyObject_GetAttrString(inst,mname);

  if (!PyCallable_Check(method)) {
    croak("Attempted to call non-method '%s'", mname);
    XSRETURN_EMPTY;
  }

  tuple = PyTuple_New(items-NUM_FIXED_ARGS);
  for (i=NUM_FIXED_ARGS; i<items; i++) {
    PyObject *o = Pl2Py(ST(i));
    if (o) {
      PyTuple_SetItem(tuple, i-NUM_FIXED_ARGS, o);
    }
  }

  Printf(("calling func\n"));
  py_retval = PyObject_CallObject(method, tuple);
  Printf(("received a response\n"));
  if (!py_retval || (PyErr_Occurred() != NULL)) {
    PyErr_Print();
    Py_DECREF(tuple);
    Py_DECREF(method);
    croak("PyObject_CallObject(...) failed.\n");
    XSRETURN_EMPTY;
  }

  Printf(("no error\n"));
#ifdef CHECK_CONTEXT
  /* We can save a little time by checking our context */
  if (GIMME_V == G_VOID)
    XSRETURN_EMPTY;
#endif

  Printf(("calling Py2Pl()\n"));
  ret = Py2Pl(py_retval);
  Py_DECREF(py_retval);
  
  if (
#ifdef CHECK_CONTEXT
      GIMME_V == G_ARRAY && 
#endif
      SvROK(ret) && (SvTYPE(SvRV(ret)) == SVt_PVAV)) {
    /* if it is an array, return the array elements ourselves. */
    AV* av = (AV*)SvRV(ret);
    int len = av_len(av) + 1;
    int i;
    for (i=0; i<len; i++) {
      XPUSHs(sv_2mortal(av_shift(av)));
    }
  } else {
    XPUSHs(ret);
  }

MODULE = Inline::Python   PACKAGE = Inline::Python::Object

void
DESTROY(obj)
        SV* obj;
  CODE:
      if (SvROK(obj) && SvTYPE(SvRV(obj))==SVt_PVMG) {
        SV* obj_deref = SvRV(obj);
        IV ptr = SvIV(obj_deref);
        PyObject *py_object;
        if (!ptr) {
          croak("destroy_python_object caught NULL PyObject pointer. Are you using a Python object?\n");
        }
        py_object = (PyObject*)ptr;
        Py_DECREF(py_object);
      }
