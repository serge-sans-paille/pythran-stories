Basic Value Range Analysis
##########################

:date: 2020-04-23
:category: compilation
:lang: en
:authors: serge-sans-paille
:summary: Pythran recently gained a significant improvment in its value range
          analysis. Let's discuss some implementation details through a bunch of
          examples.

Not every story begins with an issue, but this one does. And with a quite old
one! `#1059 <https://github.com/serge-sans-paille/pythran/issues/1059>`_ dates
back to October, 2018 :-) At that time, I was trying to efficiently compile some
kernels for a `scikit-image PR <https://github.com/scikit-image/scikit-image/pull/3226>`_.

``_integ`` function from scikit-image
=====================================

This is the body of the ``_integ`` function, from the ``_hessian_det_appx.pyx``
file in `scikit-image <https://scikit-image.org/>`_. The original body is
written in `cython <https://cython.org/>`_, with a few annotations:

.. code-block:: cython

    # cython: wraparound=False

    cdef inline Py_ssize_t _clip(Py_ssize_t x, Py_ssize_t low, Py_ssize_t high) nogil:
        if(x > high):
            return high
        if(x < low):
            return low
        return x


    cdef inline cnp.double_t _integ(cnp.double_t[:, ::1] img, Py_ssize_t r, Py_ssize_t c, Py_ssize_t rl, Py_ssize_t cl) nogil:

        r = _clip(r, 0, img.shape[0] - 1)
        c = _clip(c, 0, img.shape[1] - 1)

        r2 = _clip(r + rl, 0, img.shape[0] - 1)
        c2 = _clip(c + cl, 0, img.shape[1] - 1)

        cdef cnp.double_t ans = img[r, c] + img[r2, c2] - img[r, c2] - img[r2, c]

        if (ans < 0):
            return 0
        return ans

The translation to python, and thus to pythran, would be:

.. code-block:: python

    #pythran export _integ(float64[::], int, int, int, int)
    import numpy as np
    def _clip(x, low, high):
        assert 0 <= low <= high
        if x > high:
            return high
        if x < low:
            return low
        return x

    def _integ(img, r, c, rl, cl):
        r = _clip(r, 0, img.shape[0] - 1)
        c = _clip(c, 0, img.shape[1] - 1)

        r2 = _clip(r + rl, 0, img.shape[0] - 1)
        c2 = _clip(c + cl, 0, img.shape[1] - 1)

        ans = img[r, c] + img[r2, c2] - img[r, c2] - img[r2, c]
        return max(0, ans)

Very little changes here: the type annotations disappear, as Pythran infers them
from the top-level function and its ``pythran export`` line. All Pythran
functions are ``nogil`` by default (this is a strong requirement).

The ``wraparound=False`` comment also get removed, and an assert got added.
That's the core of this post: range value analysis and its use to detect
wraparound.
Basically, Pythran supports wraparound by default to match Python's indexing
behavior. But to avoid the test cost, it also tries hard to compute the possible
value range for each expression in the AST.

In the case of ``_integ``, it would be great if Pythran could prove that, once
clipped, ``r``, ``c``, ``r2`` and ``c2`` are all positive, that way no check
would be needed. However, to know that, we need to know that ``low >= 0``. This
property always hold at the call site, but doing a call-site specific analysis
would be too much, so a gentle ``assert`` is helpful here.

Note that it's still valid Python, and Pythran can enable or disable asserts
using ``-DNDEBUG`` or ``-UNDEBUG``, so there's no extra cost for an assert.

Thanks to the assert, and to `PR #1522
<https://github.com/serge-sans-paille/pythran/pull/1522>`_ Pythran can compute
that ``_clip`` always returns a positive value, thus deducing that no wraparound
is involved. Note that each indexing expression is handled independently, unlike
the global ``wraparound=False`` decorator.


Going further
=============

Pythran range analysis is relatively simple: it does not support symbolic bounds
and only manipulates intervals. It is interprocedural given it computes the
range of the output, but without any assumption on the range of the arguments,
and the interprocedural analysis is not recursive. It has some built-in knowledge
about the value range of functions like ``len`` and ``range``, which proves to
be useful for practical cases.

Let's illustrate that analysis through an example:

.. code-block:: python

    def foo(a):
        assert a > 0
        b = c = 10
        while a > 0:
            a -= 1
            b += 1
        if b == 9:
            print("wtf")
        if b == 10:
            print("wtf")
        if b == 11:
            print("ok")
        return a, b, c

Running this code through ``pythran -P``, which optimizes the code
then prints the python code back, gives:

.. code-block:: python

    def foo(a):
        a_ = a
        assert (a_ > 0)
        b = 10
        while (a_ > 0):
            a_ -= 1
            b += 1
        if (b == 11):
            builtins.print('ok')
        return (a_, b, 10)

The two first prints have been removed, because they were guarded by conditions
that never hold. ``b == 9`` never holds because ``b`` starts at ``10`` and
only grows. ``b == 10`` never holds either because the while loop is always
entered at least once, and Pythran knows that thanks to the ``assert``.

And as Pythran doesn't perform any kind of modelisation of the accumulation in
``a`` and ``b``, it cannot get smarter than this, but well, that's already a
decent start ;-)

Conclusion
==========

Use ``assert`` statements! Pythran can extract precious information from them,
and there's no runtime cost unless you ask so ;-)
