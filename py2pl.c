#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "Python.h"
#include "py2pl.h"
#include "util.h"

#ifdef EXPOSE_PERL
#include "perlmodule.h"
#endif

/****************************
 * SV* Py2Pl(PyObject *obj) 
 * 
 * Converts arbitrary Python data structures to Perl data structures
 * Note on references: does not Py_DECREF(obj).
 ****************************/
SV* Py2Pl (PyObject *obj) {

#ifdef EXPOSE_PERL
    /* unwrap Perl objects */
    if (PerlObjObject_Check(obj)) {
      return ((PerlObj_object *)obj)->obj;
    }

    /* unwrap Perl code refs */
    else if (PerlSubObject_Check(obj)) {
      return ((PerlSub_object *)obj)->ref;
    }

    else
#endif

    /* wrap an instance of a Python class */
    if (PyInstance_Check(obj)) {

      /* This is a Python class instance -- bless it into an
       * Inline::Python::Object. If we're being called from an
       * Inline::Python class, it will be re-blessed into whatever
       * class that is.
       */
      SV *inst_ptr = newSViv(0);
      SV *inst;
      MAGIC *mg;
      _inline_magic priv;

      inst = newSVrv(inst_ptr, "Inline::Python::Object");

      /* set up magic */
      priv.key = INLINE_MAGIC_KEY;
      sv_magic(inst, inst, '~', (char*)&priv, sizeof(priv));
      mg = mg_find(inst, '~');
      mg->mg_virtual = (MGVTBL*)malloc(sizeof(MGVTBL));
      mg->mg_virtual->svt_free = free_inline_py_obj;

      sv_setiv(inst, (IV)obj);
      /*SvREADONLY_on(inst);*/ /* to uncomment this means I can't
				  re-bless it */
      Py_INCREF(obj);
      return inst_ptr;
    }

    /* a tuple or a list */
    else if (PySequence_Check(obj) && !PyString_Check(obj)) {
       AV *retval = newAV();
       int i;
       int sz = PySequence_Length(obj);

       Printf(("sequence (%i)\n",sz));

       for (i=0; i<sz; i++) {
         PyObject *tmp = PySequence_GetItem(obj,i); /* new reference */
         SV* next = Py2Pl(tmp);
         av_push(retval, next);
         Py_DECREF(tmp);
       }
       return newRV_noinc((SV*) retval);
    }

    /* a dictionary or fake Mapping object */
    else if (PyMapping_Check(obj)) {
       HV *retval = newHV();
       int i;
       int sz = PyMapping_Length(obj);
       PyObject *keys = PyMapping_Keys(obj);              /* new reference */
       PyObject *vals = PyMapping_Values(obj);            /* new reference */

       Printf(("mapping (%i)\n",sz));

       for (i=0; i<sz; i++) {
           PyObject *key = PySequence_GetItem(keys,i);    /* new reference */
           PyObject *val = PySequence_GetItem(vals,i);    /* new reference */
       
           SV* sv_val = Py2Pl(val);
           char *key_val;
       
           if (!PyString_Check(key)) {
             /* Warning -- encountered a non-string key value while converting a 
              * Python dictionary into a Perl hash. Perl can only use strings as 
              * key values. Using Python's string representation of the key as 
              * Perl's key value.
              */
             PyObject *s = PyObject_Str(key);
	     key_val = PyString_AsString(s);
             Py_DECREF(s);
	     if (PL_dowarn)
		warn("Stringifying non-string hash key value: '%s'", key_val);
           }
             else {
             key_val = PyString_AsString(key);
           }

           if (!key_val) {
	     croak("Invalid key on key %i of mapping\n", i);
           }

           hv_store(retval, key_val, strlen(key_val), sv_val, 0);
           Py_DECREF(key);
           Py_DECREF(val);
       }
       Py_DECREF(keys);
       Py_DECREF(vals);
       return newRV_noinc((SV*)retval);
    }

    /* None (like undef) */
    else if (obj == Py_None) {
      return &PL_sv_undef;
    }

    /* a string (or number) */
    else {
       PyObject *string = PyObject_Str(obj);  /* new reference */
       char *str = PyString_AsString(string);
       SV* s2 = newSVpv(str,PyString_Size(string));
       Py_DECREF(string);
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

   /* an object */
   if (sv_isobject(obj)) {

     /* We know it's a blessed reference:
      * Now it's time to check whether it's *really* a blessed Perl object,
      * or whether it's a blessed Python object with '~' magic set.
      * If '~' magic is set, we 'unwrap' it into its Python object. 
      * If not, we wrap it up in a PerlObj_object. */

      SV* obj_deref = SvRV(obj);

      /* check for magic! */

      MAGIC *mg = mg_find(obj_deref, '~');
      if (mg && Inline_Magic_Check(mg->mg_ptr)) {
	IV ptr = SvIV(obj_deref);
	if (!ptr) {
	  croak("Internal error: Pl2Py() caught NULL PyObject* at %s, line %s.\n",
		__FILE__, __LINE__);
	}
	o = (PyObject*)ptr;
      }
      else {
	HV* stash = SvSTASH(obj_deref);
	char *pkg = HvNAME(stash);
	SV *full_pkg = newSVpvf("main::%s::", pkg);
	PyObject *pkg_py;

	Printf(("A Perl object (%s). Wrapping...\n", SvPV(full_pkg, PL_na)));

	pkg_py = PyString_FromString(SvPV(full_pkg, PL_na));
	o = newPerlObj_object(obj, pkg_py);

	Py_DECREF(pkg_py);
	SvREFCNT_dec(full_pkg);
      }
   }

   /* An integer */
   else if (SvIOKp(obj)) {
      Printf(("integer\n"));
      o = PyInt_FromLong((long)SvIV(obj)); 
   }
   /* A floating-point number */
   else if (SvNOKp(obj)) {
      PyObject *tmp = PyString_FromString(SvPV_nolen(obj));
      Printf(("float\n"));
      if (tmp)
	o = PyNumber_Float(tmp);
      else {
	 fprintf(stderr, "Internal Error --");
	 fprintf(stderr, "your Perl string \"%s\" could not \n", SvPV_nolen(obj));
         fprintf(stderr, "be converted to a Python string\n");
      }
      Py_DECREF(tmp);
   }
   /* A string */
   else if (SvPOKp(obj)) {
      STRLEN len;
      char *str = SvPV(obj, len);
      Printf(("string = "));
      Printf(("%s\n", str));
      o = PyString_FromStringAndSize(str, len);
      Printf(("string ok\n"));
   }
   /* An array */
   else if (SvROK(obj) && SvTYPE(SvRV(obj))==SVt_PVAV) {
      AV* av = (AV*) SvRV(obj);
      int i;
      int len = av_len(av) + 1;
      o = PyTuple_New(len);

      Printf(("array (%i)\n", len));

      for (i=0; i<len; i++) {
          SV *tmp = av_shift(av);
          PyTuple_SetItem(o,i,Pl2Py(tmp));
      }
   }
   /* A hash */
   else if (SvROK(obj) && SvTYPE(SvRV(obj))==SVt_PVHV) {
      HV* hv = (HV*) SvRV(obj);
      int len = hv_iterinit(hv);
      int i;

      o = PyDict_New();

      Printf(("hash (%i)\n", len));

      for (i=0; i<len; i++) {
          HE *next = hv_iternext(hv);
          I32 n_a;
          char *key = hv_iterkey(next,&n_a);
          PyObject *val = Pl2Py ( hv_iterval(hv, next) );
	  PyDict_SetItemString(o,key,val); 
          Py_DECREF(val);                              
      }

      Printf(("returning from hash conversion.\n"));

   }
   /* A code ref */
   else if (SvROK(obj) && SvTYPE(SvRV(obj))==SVt_PVCV) {
     /* wrap this into a PerlSub_object */

     o = (PyObject*)newPerlSub_object(NULL, NULL, obj);
   }

   else {
     o = Py_None;
     Py_INCREF(Py_None);
   }
   Printf(("returning from Pl2Py\n"));
   return o;
}
