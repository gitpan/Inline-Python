#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "Python.h"

int _python_argc;
char *_python_argv[] = {
  "python",
};

#define DECREF(x) { Py_DECREF(x); }
#define Printf(format,args...) {  }
//#define Printf printf

#ifndef SvPV_nolen
static STRLEN n_a;
#define SvPV_nolen(x) SvPV(x,n_a)
#endif

/****************************
 * SV* Py2Pl(PyObject *obj) 
 * 
 * Converts arbitrary Python data structures to Perl data structures
 * Note on references: does not Py_DECREF(obj).
 ****************************/
SV* Py2Pl (PyObject *obj, char *perl_class) {
   /* Here is how it does it:
    * o If obj is a String, Integer, or Float, we convert it to an SV;
    * o If obj is a List or Tuple, we convert it to an AV;
    * o If obj is a Dictionary, we convert it to an HV.
    */
    if (PyInstance_Check(obj)) {
      /* This is a Python class instance -- bless it into a Perl package */
      SV *inst_ptr = newSViv(0);
      SV *inst = newSVrv(inst_ptr, perl_class);
      sv_setiv(inst, (IV)obj);
      SvREADONLY_on(inst);
      return inst_ptr;
    }
    else if (PySequence_Check(obj) && !PyString_Check(obj)) {
       AV *retval = newAV();
       int i;
       int sz = PySequence_Length(obj);

       Printf("sequence (%i)\n",sz);

       for (i=0; i<sz; i++) {
         PyObject *tmp = PySequence_GetItem(obj,i); /* new reference */
         SV* next = Py2Pl(tmp,perl_class);
         av_push(retval, next);
         DECREF(tmp);
       }
       return newRV_noinc((SV*) retval);
    }
    else if (PyMapping_Check(obj)) {
       HV *retval = newHV();
       int i;
       int sz = PyMapping_Length(obj);
       PyObject *keys = PyMapping_Keys(obj);              /* new reference */
       PyObject *vals = PyMapping_Values(obj);            /* new reference */

       Printf("mapping (%i)\n",sz);

       for (i=0; i<sz; i++) {
           PyObject *key = PySequence_GetItem(keys,i);    /* new reference */
           PyObject *val = PySequence_GetItem(vals,i);    /* new reference */
       
           SV* sv_val = Py2Pl(val,perl_class);
           U32 hash;
           char *key_val;
       
           if (!PyString_Check(key)) {
             /* Warning -- encountered a non-string key value while converting a 
              * Python dictionary into a Perl hash. Perl can only use strings as 
              * key values. Using Python's string representation of the key as 
              * Perl's key value.
              */
             PyObject *s = PyObject_Str(key);
	     key_val = PyString_AsString(s);
             DECREF(s);
           }
             else {
             key_val = PyString_AsString(key);
           }

           if (!key_val) {
              croak("Invalid key on %i%s key of mapping\n", i, i ? ( (i==1) ? "st" : ( (i==2) ? "nd" : ( (i==3) ? "rd" : "th"))) : "th");
           }

           PERL_HASH(hash,key_val,strlen(key_val));
           hv_store(retval,key_val,strlen(key_val),sv_val,hash);
           DECREF(key);
           DECREF(val);
       }
       DECREF(keys);
       DECREF(vals);
       return newRV_noinc((SV*)retval);
    }
    else {
       PyObject *string = PyObject_Str(obj);  /* new reference */
       char *str = PyString_AsString(string);
       SV* s2 = newSVpv(str,0);
       DECREF(string);
       return s2;
    }
}

/****************************
 * SV* Pl2Py(PyObject *obj) 
 * 
 * Converts arbitrary Perl data structures to Python data structures
 ****************************/
PyObject *Pl2Py (SV *obj) {
   PyObject *o;

   if (SvIOKp(obj)) {
      Printf("integer\n");
      o = PyInt_FromLong((long)SvIV(obj)); 
   }
   else if (SvNOKp(obj)) { 
      PyObject *tmp = PyString_FromString(SvPV_nolen(obj));
      Printf("float\n");
      if (tmp)
	o = PyNumber_Float(tmp);
      else {
	 fprintf(stderr, "Internal Error --");
	 fprintf(stderr, "your Perl string \"%s\" could not \n", SvPV_nolen(obj));
         fprintf(stderr, "be converted to a Python string\n");
      }
      DECREF(tmp);
   }
   else if (SvPOKp(obj)) {
      char *str = SvPV_nolen(obj);
      Printf("string = ");
      Printf("%s\n", str);
      o = PyString_FromString(str);
      Printf("string ok\n");
   }
   else if (SvROK(obj) && SvTYPE(SvRV(obj))==SVt_PVAV) {
      AV* av = (AV*) SvRV(obj);
      int i;
      int len = av_len(av) + 1;
      o = PyTuple_New(len);

      Printf("array (%i)\n", len);

      for (i=0; i<len; i++) {
          SV *tmp = av_shift(av);
          PyTuple_SetItem(o,i,Pl2Py(tmp));
      }
   } 
   else if (SvROK(obj) && SvTYPE(SvRV(obj))==SVt_PVHV) {
      HV* hv = (HV*) SvRV(obj);
      PyObject *dict = PyDict_New();
      int len = hv_iterinit(hv);
      int i;

      Printf("hash (%i)\n", len);

      for (i=0; i<len; i++) {
          HE *next = hv_iternext(hv);
          I32 n_a;
          char *key = hv_iterkey(next,&n_a);
          PyObject *val = Pl2Py ( hv_iterval(hv, next) );
	  PyDict_SetItemString(dict,key,val); 
          DECREF(val);                              
      }

      Printf("returning from hash conversion.\n");

      return dict;
   }
   else if (SvROK(obj) && SvTYPE(SvRV(obj))==SVt_PVMG) {
      /* this is a blessed scalar -- hopefully the scalar contains a PyObject*
       * which we can dereference and return as-is. 
       */
      SV* obj_deref = SvRV(obj);
      IV ptr = SvIV(obj_deref);

      if (!ptr) {
        croak("Pl2Py() caught NULL PyObject pointer. Are you using a Python object?\n");
      }
      return (PyObject*)ptr;
   }
   else {
      fprintf(stderr, "Internal error -- unsupported Perl datatype.\n");
      return PyString_FromString("Error converting perl structure.");
   }
   Printf("returning from Pl2Py\n");
   return o;
}

/* The following two functions are probably not needed, but they're
 * still here, for old time's sake :)
 */

/* returns PyObject * on success, else NULL */
PyObject *find_method(PyObject *klass, char *method) {
  PyObject *dict = PyObject_GetAttrString(klass, "__dict__");
  int dict_len = PyObject_Length(dict);
  PyObject *bases;
  int bases_len;
  int i;

  printf("scanning class: ");
  PyObject_Print(klass,stdout,0); printf("\n");

  /* first check this class */
  if (PyMapping_HasKeyString(dict,method))
    return PyMapping_GetItemString(dict,method);

  bases = PyObject_GetAttrString(klass, "__bases__");
  bases_len = PyObject_Length(bases);
  for (i=0; i<bases_len; i++) {
    PyObject *methobj = find_method(PySequence_GetItem(bases, i), method);
    if (methobj)
      return methobj;
  }
  return NULL;
}

PyObject *find_inherited_method(PyObject *instance, char *method) {
  PyObject *klass = PyObject_GetAttrString(instance, "__class__");
  PyObject *bases = PyObject_GetAttrString(klass, "__bases__");

  int num_bases = PyObject_Length(bases);
  int i;

  printf("find_inherited_method(");
  PyObject_Print(instance,stdout,0);
  printf("%s)\n",method);

  for (i=0; i<num_bases; i++) {
    PyObject *methobj = find_method(PySequence_GetItem(bases, i), method);
    if (methobj)
      return methobj;
  }
  return NULL;
}

MODULE = Inline::Python   PACKAGE = Inline::Python

BOOT:
Py_Initialize();
PySys_SetArgv(_python_argc, _python_argv);  /* Tk needs this */

PROTOTYPES: DISABLE

void 
_Inline_parse_python_namespace()
 PREINIT:
  PyObject *mod = PyImport_AddModule("__main__");
  PyObject *dict = PyModule_GetDict(mod);
  PyObject *keys = PyMapping_Keys(dict);
  int len = PyObject_Length(dict);
  int i;
  AV* functions = newAV();
  HV* classes = newHV();
 PPCODE:
  for (i=0; i<len; i++) {
    PyObject *key = PySequence_GetItem(keys,i);
    PyObject *val = PyObject_GetItem(dict,key);
    if (PyCallable_Check(val)) {
      if (PyFunction_Check(val)) {
        char *name = PyString_AsString(key);
        Printf("Found a function: %s\n", name);
	av_push(functions, newSVpv(name,0));
      }
      else if (PyClass_Check(val)) {
        char *name = PyString_AsString(key);
	PyObject *cls_dict = PyObject_GetAttrString(val,"__dict__");
	PyObject *cls_keys = PyMapping_Keys(cls_dict);
	int dict_len = PyObject_Length(cls_dict);
	int j;

	/* array of method names */
	AV* methods = newAV();
	AV* bases = newAV();
	U32 hash;

	Printf("Found a class: %s\n", name);

	/* populate the array */
	for (j=0; j<dict_len; j++) {
	  PyObject *cls_key = PySequence_GetItem(cls_keys,j);
	  PyObject *cls_val = PyObject_GetItem(cls_dict,cls_key);
	  char *fname = PyString_AsString(cls_key);
	  if (PyFunction_Check(cls_val)) {
	    Printf("Found a method of %s: %s\n", name, fname);
	    av_push(methods,newSVpv(fname,0));
	  }
	}

	PERL_HASH(hash, name, strlen(name));
	hv_store(classes,name,strlen(name),newRV_noinc((SV*)methods),hash);
      }
    }
  }
  /* return an expanded hash */
  PUSHs(newSVpv("functions",0));
  PUSHs(newRV_noinc((SV*)functions));
  PUSHs(newSVpv("classes", 0));
  PUSHs(newRV_noinc((SV*)classes));

int 
_eval_python(x)
	char *x;
    CODE:
	RETVAL = (PyRun_SimpleString(x) >= 0);
    OUTPUT:
	RETVAL

void 
_destroy_python_object(obj)
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
        DECREF(py_object);
      }

void
_eval_python_function(PKG, FNAME...)
     char*    PKG;
     char*    FNAME;
  PREINIT:
  int i;

  PyObject *mod       = PyImport_AddModule("__main__");
  PyObject *dict      = PyModule_GetDict(mod);
  PyObject *func      = PyMapping_GetItemString(dict,FNAME);
  PyObject *o         = NULL;
  PyObject *py_retval = NULL;
  PyObject *tuple     = NULL;

  SV* ret = NULL;

  PPCODE:

  Printf("function: %s\n", FNAME);

  if (!PyCallable_Check(func)) {
    warn("Error -- Python function %s is not a callable object\n",
	 FNAME);
    XSRETURN_EMPTY;
  }

  Printf("function is callable!\n");
  
  tuple = PyTuple_New(items-2);
  
  for (i=2; i<items; i++) {
    o = Pl2Py(ST(i));
    if (o) {
      PyTuple_SetItem(tuple, i-2, o);
    }
  }
  Printf("calling func\n");
  py_retval = PyObject_CallObject(func, tuple);
  Printf("received a response\n");
  if (!py_retval || (PyErr_Occurred() != NULL)) {
    PyErr_Print();
    DECREF(tuple);
    DECREF(func);
    croak("Error -- PyObject_CallObject(...) failed.\n");
    XSRETURN_EMPTY;
  }
  Printf("no error -- calling Py2Pl()\n");
  ret = Py2Pl(py_retval, PKG);
  if (!PyClass_Check(func))
    DECREF(py_retval); /* don't decrement it if we're saving it for later */
  
  if (SvROK(ret) && (SvTYPE(SvRV(ret)) == SVt_PVAV)) {
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

void
_eval_python_method(pkg, mname, _inst, ...)
	char*	pkg;
	char*	mname;
	SV*	_inst;
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

  Printf("eval_python_method\n");

  if (SvROK(_inst) && SvTYPE(SvRV(_inst))==SVt_PVMG) {
    inst = (PyObject*)SvIV(SvRV(_inst));
  }

  if (!PyInstance_Check(inst)) {
    warn("Error -- Python_Call_Method() must receive a Python class instance!\n");
    XSRETURN_EMPTY;
  }

  if (!PyObject_HasAttrString(inst, mname)) {
    warn("Error -- Python object has no method named %s", mname);
    XSRETURN_EMPTY;
  }

  method = PyObject_GetAttrString(inst,mname);
  tuple = PyTuple_New(items-3);
  for (i=3; i<items; i++) {
    PyObject *o = Pl2Py(ST(i));
    if (o) {
      PyTuple_SetItem(tuple, i-3, o);
    }
  }

  Printf("calling func\n");
  py_retval = PyObject_CallObject(method, tuple);
  Printf("received a response\n");
  if (!py_retval && (PyErr_Occurred() != NULL)) {
    PyErr_Print();
    DECREF(tuple);
    DECREF(method);
    croak("Error -- PyObject_CallObject(...) failed.\n");
    XSRETURN_EMPTY;
  }
  Printf("no error -- calling Py2Pl()\n");
  ret = Py2Pl(py_retval, pkg);
  DECREF(py_retval);
  
  if (SvROK(ret) && (SvTYPE(SvRV(ret)) == SVt_PVAV)) {
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

