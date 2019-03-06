Source-to-source transformation of a Python kernel
##################################################

:date: 2019-03-06
:category: compilation
:lang: en
:authors: serge-sans-paille
:summary: Pythran can also be used as a source-to-source transformation engine.
          This post showcases some recent transformation on a high-level code.

If you're curious or genuinely interested into how Pythran transforms your
code, but not brave enough to dive into the generated C++ code, Pythran
provides a compilation switch to dump the refined Python code, after
optimization and before it gets translated to C++. Internally, this relies on
the fact we have to backends: a C++ backend and a Python backend.

Using Pythran as a Source-to-Source Compiler
============================================

Pythran can be used as a source-to-source engine through the ``-P`` flag.

.. code-block:: shell

    > cat sample.py
    def fibo(n):
        return n if n < 2 else fibo(n - 1) + fibo(n - 2)
    def test():
        print(fibo(10))
    > pythran -P sample.py
    def fibo(n):
        return (n if (n < 2) else (fibo((n - 1)) + fibo((n - 2))))
    def test():
        __builtin__.print(55)
        return __builtin__.None

What happened? Pythran analyzed the body of ``fibo`` and found out it was a
pure function (no effect on global state nor arguments) called with a literal,
so it performed aggressive constant propagation. It also computed variable
scope and made any builtin explicit (``__builtin__.print``) and computed the
control flow graph of each function, adding ``return None`` wherever Python
would implicit add it.

Advanced Transformations
========================

An alluring aspect of Python for scientists is the high level constructs it
proposes. For instance, the following code implements an (arguably) high level
way of computing the wighted sum between five integers:

.. code-block:: python

    # wsum.py
    import numpy as np
    def wsum(v, w, x, y, z):
        return sum(np.array([v, w, x, y, z]) * (.1, .2, .3, .2, .1))

This code is okay from Numpy point of view, but how does Pythran handle it?
Surely, building a temporary array just for the sake of performing a
point-to-point array operation is not the most efficient way of performing
these operation!

.. code-block:: shell

    > pythran -P wsum.py
    import numpy as __pythran_import_numpy
    def wsum(v, w, x, y, z):
        return __builtin__.sum(((v * 0.1), (w * 0.2), (x * 0.3), (y * 0.2), (z * 0.1)))

Fascinating! (Yes, I'm auto-congratulating there). Pythran understood that a
Numpy operation on fixed-size array was involved, so it first performed the
broadcasting on its own, resulting in:

.. code-block:: python

    import numpy as __pythran_import_numpy
    def wsum(v, w, x, y, z):
        return __builtin__.sum(__pythran_import_numpy.array([(v * 0.1), (w * 0.2), (x * 0.3), (y * 0.2), (z * 0.1)]))

Then it used the fact that sum can take any iterable as parameter to prune the
call to ``np.array``. The nice thing with tuple of homogeneous type as
parameter is that the C++ backend can use it to generate something equivalent
to ``std::array<double, 5>``, avoiding a memory allocation.

The Assembly Worker
===================

Let's inspect the assembly generated from the above code, instantiated with the
Pythran annotation ``#pythran export wsum(float64, float64, float64, float64,
float64)`` and compiled with Clang 6.0

.. code-block:: shell

    > CXX=clang++ pythran wsum.py
    > objdump -S -C wsum.*.so
    [...]
    ...  movsd  0x12d4(%rip),%xmm0
    ...  movsd  0x18(%rsp),%xmm2
    ...  mulsd  %xmm0,%xmm2
    ...  movsd  0x12ca(%rip),%xmm1
    ...  movsd  0x10(%rsp),%xmm3
    ...  mulsd  %xmm1,%xmm3
    ...  movsd  0x8(%rsp),%xmm4
    ...  mulsd  0x12ba(%rip),%xmm4
    ...  movsd  (%rsp),%xmm5
    ...  mulsd  %xmm0,%xmm5
    ...  movsd  0x20(%rsp),%xmm0
    ...  mulsd  %xmm1,%xmm0
    ...  addsd  %xmm5,%xmm0
    ...  addsd  %xmm4,%xmm0
    ...  addsd  %xmm3,%xmm0
    ...  addsd  %xmm2,%xmm0
    [...]

No single call to a memory allocator, no branching, just a plain listing of
``movsd``, ``mulsd`` and ``addsd``. And quite some register pressure, but
that's how it is.

Just ``perf`` it
================

As a tribute to Victor Stinner's ``perf`` module, and as a conclusion to this
small experiment, let's ensure we get some speedup, event for such a small
kernel:

.. code-block:: shell

    > rm *.so
    > python -m perf timeit -s 'from wsum import wsum' 'wsum(1.,2.,3.,4.,5.)'
    .....................
    Mean +- std dev: 3.73 us +- 0.11 us
    > CXX=clang++ pythran wsum.py
    > python -m perf timeit -s 'from wsum import wsum' 'wsum(1.,2.,3.,4.,5.)'
    .....................
    Mean +- std dev: 190 ns +- 3 ns

And out of curiosity, let's check the timing with the transformed Python kernel.

.. code-block:: shell

    > rm *.so
    > pythran -P wsum.py | sed 's,__builtin__.,,' > wsum2.py
    > python -m perf timeit -s 'from wsum2 import wsum' 'wsum(1.,2.,3.,4.,5.)'  
    .....................
    Mean +- std dev: 308 ns +- 7 ns

Fine! Pythran did the job in both cases :-)

Final Words
===========

The optimisations done by Pythran are meant at optimising its internal
representation so that translated code compiles to an efficient native library.
Still, being able to debug it at Python level is very valuable, and it can even
generate faster Python code in some cases!
