the Capsule Corporation
#######################

:date: 2017-11-08
:category: engineering
:lang: en
:authors: serge-sans-paille
:summary: Python provides a convenient way to encapsulate a raw pointer in an
          object, to make interaction between native modules easier. SciPy uses that
          mechanism to call native code from some functions, and now Pythran
          can produce them just as well as Dr Brief would!

This post is not about the famous `Hoi-Poi Capsule <http://dragonball.wikia.com/wiki/Capsule>`_ but about a feature I recently discovered from Python: `PyCapsule <https://docs.python.org/3.1/c-api/capsule.html>`_. From the doc:

    This subtype of PyObject represents an opaque value, useful for C extension modules who need to pass an opaque value (as a void* pointer) through Python code to other C code.

It turns out it's used in at least one situation relevant to Pythran: as a parameter of SciPy's `LowLevelCallable <https://docs.scipy.org/doc/scipy/reference/generated/scipy.LowLevelCallable.html>`_. Thanks to this mechanics, some SciPy function written as C extensions can call function written in another functions without any Python conversion in-between.

I reproduce an example from an `official SciPy tutorial  <https://scipy.github.io/devdocs/tutorial/integrate.html#faster-integration-using-low-level-callback-functions>`_ as an example.
The following code is going to be compiled as a shared library through ``$ gcc -shared -fPIC -o testlib.so testlib.c -O2``

.. code-block:: c

    /* testlib.c */
    double f(int n, double *x, void *user_data) {
        double c = *(double *)user_data;
        return c + x[0] - x[1] * x[2]; /* corresponds to c + x - y * z */
    }

It is then loaded through ``ctypes`` and used as a parameter to ``scipy.integrate``

.. code-block:: python

    import os, ctypes
    from scipy import integrate, LowLevelCallable

    lib = ctypes.CDLL(os.path.abspath('testlib.so'))
    lib.f.restype = ctypes.c_double
    lib.f.argtypes = (ctypes.c_int, ctypes.POINTER(ctypes.c_double), ctypes.c_void_p)

    c = ctypes.c_double(1.0)
    user_data = ctypes.cast(ctypes.pointer(c), ctypes.c_void_p)

    func = LowLevelCallable(lib.f, user_data)

A quick'n dirty benchmark gives a hint about the raw performance of the process:

.. code-block:: python

    >>> dat =  [[0, 10], [-10, 0], [-1, 1]]
    >>> %timeit integrate.nquad(func, dat)
    1000 loops, best of 3: 1.78 ms per loop

Using Pythran to generate a capsule
===================================

The whole purpose of Pythran is to avoid writing any C code at all. An equivalent of ``testlib.so`` can be derived from the following Python code annotated with a ``pythran export``,
using ``$ pythran testlib.py -O2`` to produce a shared library ``testlib.so``.

.. code:: python

    # testlib.py
    #pythran export f(int, float64 [], float64 [])
    def f(n, x, cp):
        c = cp[0]
        return c + x[0] - x[1] * x[2]


Unfortunately the generated function still performs conversion from Python data to native data, before running the native code. So it's not a good candidate for ``ctypes`` importation at all.

Something I like to say about Pythran is that it converts Python programs into
C++ meta-programs that are instantiated for the types given in the ``pythran
export`` lines. And that's definitively a useful thing[0], as it is dead easy
to change its interface to generate Python-free functions. With a bit of syntactic sugar, it gives the following:

.. code:: python

    # testlib.py
    #pythran export capsule f(int32, float64*, float64* )
    def f(n, x, cp):
        c = cp[0]
        return c + x[0] - x[1] * x[2]

Only the Pythran comment changes, the Python code is unchanged and the resulting function ``f`` is not even, it's actually a capsule:

.. code:: python

    >>> from testlib import f
    >>> f
    <capsule object "f(int, float64*, float64*)" at 0x7f554d69f840>

SciPy's ``LowLevelCallable`` also support capsule as a way to access function pointers:

.. code:: python

    >>> c = ctypes.c_double(1.0)
    >>> user_data = ctypes.cast(ctypes.pointer(c), ctypes.c_void_p)
    >>> func = LowLevelCallable(f, user_data, signature="double (int, double *, void *)")

Then we can run the same benchmark as above:

.. code:: python

    >>> dat =  [[0, 10], [-10, 0], [-1, 1]]
    >>> %timeit integrate.nquad(func, dat)
    1000 loops, best of 3: 1.75 ms per loop

Cool, the same performance, while keeping Python-compatible code ``\o/``.

Capsule and Numpy
=================

There is another interesting usage example in the `SciPy documentation
<https://docs.scipy.org/doc/scipy/reference/tutorial/ndimage.html#ndimage-ccallbacks>`_.
In that example, the capsule creation is purely done in C, using the Python C
API. Let's see how we can achieve the same result with Pythran. The original C routine is the following:

.. code:: C

    static int
    _transform(npy_intp *output_coordinates, double *input_coordinates, int output_rank, int input_rank, void *user_data)
    {
        npy_intp i;
        double shift = *(double *)user_data;

        for (i = 0; i < input_rank; i++) {
            input_coordinates[i] = output_coordinates[i] - shift;
        }
        return 1;
    }

Using Pythran and Numpy, it is possible to write a portable version like this:

.. code:: python

    from numpy.ctypeslib import as_array
    def transform(output_coordinates, input_coordinates, output_rank, input_rank, user_data):
        shift = user_data[0]
        input_data = as_array(input_coordinates, input_rank)
        output_data = as_array(output_coordinates, output_rank)
        input_data[:] = output_data - shift
        return 1

    def transform_basic(output_coordinates, input_coordinates, output_rank, input_rank, user_data):
        shift = user_data[0]
        for i in range(input_rank):
            input_coordinates[i] = output_coordinates[i] - shift;
        return 1

Note that thanks to ``numpy.ctypeslib`` that's still 100% pure Python code, using official APIs.

The export line to create a capsule is:

.. code:: python

    #pythran export capsule transform(int64*, float64*, int32, int32, float64*)
    #pythran export capsule transform_basic(int64*, float64*, int32, int32, float64*)

Once compiled with Pythran, we get a native library that can be imported and used in a Python script:

.. code:: python

    import ctypes
    import numpy as np
    from scipy import ndimage, LowLevelCallable

    from example import transform

    shift = 0.5

    user_data = ctypes.c_double(shift)
    ptr = ctypes.cast(ctypes.pointer(user_data), ctypes.c_void_p)
    callback = LowLevelCallable(transform, ptr, "int (npy_intp *, double *, int, int, void *)")
    im = np.arange(12).reshape(4, 3).astype(np.float64)
    print(ndimage.geometric_transform(im, callback))

Performance wise, the version based on Numpy array is still slightly lagging
behind because of the extra array creation (it initializes a here useless
memory management part), and the other version is equivalent to the one written
in C.


Pitfalls and Booby Traps
========================

Using a ``PyCapsule`` requires some care, as the user (**you**) needs to take care of correctly mapping the native arguments:

1. The signature passed to ``LowLevelCallable`` needs to be exactly the one required by SciPy. Not a single extra white space is allowed!

2. Changing the Pythran annotation to ``#pythran export f(int32, float64 [], float32[])`` does not yield any error (no type checking can done when matching this to the ``LowLevelCallable`` signature) but the actual result is incorrect. Indeed, aliasing a ``float32*`` to a ``float64*`` is incorrect!

3. The pointer types in the Pythran annotation are only meaningful within a capsule. There is *currently* no way to use them in regular Pythran functions.

4. There is no way to put an overloaded function into a capsule (a capsule wraps a function pointer, which is incompatible with overloads).

5. Wrapping a pointer into an ``ndarray`` using ``numpy.ctypeslib.as_array`` currently implies a slight overhead :/.

Apart from that, I'm glad this new feature landed, thanks a lot to `@maartenbreddels <https://github.com/maartenbreddels>`_ for opening the `related issue <https://github.com/serge-sans-paille/pythran/issues/732>`_!


.. [0] It comes at a price though: all Pythran optimization are type agnostic, which puts a heavy burden on the compiler developper's shoulder.

