Toward a Simpler and Faster Pythran Compiler
############################################

:date: 2017-06-30
:category: engineering
:lang: en
:authors: serge-sans-paille
:summary: 6 months of tireless efforts to speedup pythran compilation time, and make the code easier to maintain.

Over the last six months, I've been working on improving Pythran for the
`OpenDreamKit <http://opendreamkit.org>`__ project. The inital goal was to add
some basic support for classes, but as it quickly turns out, that would break a
central assumption of Pythran « everything can be modeled in a procedural way »,
and breaking this assumptions implies a lot of code changes. Instead of turning
Pythran into an Idol with Feet of Clay, I began to cleanup the codebase, making
it slimmer, faster, and still generating efficient code. This brings me to this
blog post, that details various aspects of the development starting from last
stable version at `6428e526ec
<https://github.com/serge-sans-paille/pythran/commit/6428e526ec414cc79a1d2b7399137aa5e1656a2a>`_
and a recent commit, namely `3ec043e5ce
<https://github.com/serge-sans-paille/pythran/commit/3ec043e5ce0cb5b9292fa92e9fd38a01cf8122b5>`_,
used as ``HEAD`` for this post.

This blogpost is split in two sections: one concerning codebase improvement to
achieve faster compilation time, and one considering performance improvement, to
generate code that runs faster; So In the end, we get faster code, faster!

But first some statistics:

- During this period, *24* issues `have been closed <https://github.com/serge-sans-paille/pythran/issues?utf8=%E2%9C%93&q=is%3Aissue%20is%3Aclosed%20closed%3A%3E2017-01-01>`_.

- There has been more than a hundred of commits.

  .. code::

    $ git rev-list --count 6428e526ec..
    118

- If we exclude the two Boost.Simd updates, the code base has not grown much,
  which is great news, because we did fix a lot of issues, without making the
  code grow too much.

  .. code::

    $ git diff --shortstat 6428e526ec.. -- pythran
    203 files changed, 3185 insertions(+), 3119 deletions(-)

- And finally, the codebase is still within my reach, as reported by sloccount,
  roughly 45kSLOC of C++ runtime, 15kSLOC of python tests and 15kSLOC of actual
  compiler code.

  .. code::

    $ sloccount pythran
    [...]
    SLOC	Directory	SLOC-by-Language (Sorted)
    43984   pythonic        cpp=43984
    15004   tests           python=14738,cpp=232,sh=34
    7955    top_dir         python=7955
    2435    analyses        python=2435
    1923    types           python=1923
    1390    transformations python=1390
    720     optimizations   python=720


Faster Compilation
==================

If I try to compile the `kmeans.py <https://github.com/serge-sans-paille/pythran/blob/master/pythran/tests/cases/kmeans.py>`_ code from the Pythran test bed, using g++-6.3, at revision ``6428e526ec``, I roughly get (with hot file system caches):

.. code::

    $ time pythran kmeans.py
    5.69s user 0.46s system 102% cpu 5.975 total

The very same command using the ``HEAD`` revision outputs:

.. code::

    $ time pythran kmeans.py
    4.47s user 0.43s system 103% cpu 4.723 total

Wow, that's something around one second faster. Not incredible, but still 20% faster. How did this happen? (What an intro!)


Optional Typing
---------------

« The fastest program is the one that does nothing. » Inspired by this motto (and by the advices of `pbrunet <https://github.com/pbrunet>`_), I realized that current compilation flow, illustrated below:

.. code::

    ir = parse(code)
    if not type_check(ir):
        raise CompileError(...)
    cxx = generate_cxx(ir)
    compile_cxx(cxx)

could be rewritten like this:

.. code::

    ir = parse(code)
    cxx = generate_cxx(ir)
    try:
        compile_cxx(cxx)
    except SystemError:
        if not type_check(ir):
            raise CompileError(...)
        raise

Basically, the type checker is only used to produce smarter error output (see
`Previous BlogPost on the subject <../2016-12-10-pythran-typing.rst>`_
for more details), there's already a typing mechanism in Pythran that delegates
as much work as possible to C++. So the idea here is to compile things without
type checking, and if compilation fails, try hard to find the origin.

See commit `58d62de77e <https://github.com/serge-sans-paille/pythran/commit/58d62de77e14eca7210f470b5c3e851c5167e175>`_.

Sanitize Pass Pipeline
----------------------

The optimization pipeline of Pythran is driven by a pass manager that schedules
optimization passes and takes care of maintiaing the analyse cache.

The pass manager used to call ``ast.fix_missing_location`` after each
transformation, to maintain node location information, which can be useful for
error reporting and running calls to ``compile`` on ast nodes. It's now only
done if the pass actually did something.

Still in the pass management stuff, Pythran begins with a few normalization
passes to reduce the Python AST (in fact the `gast
<https://github.com/serge-sans-paille/gast>`_ one) to a friendlier IR. It turns
out this normalization pipelin had some redundant steps, that got pruned, which
avoids a few AST walk.

In the same spirit of removing useless stuff, some Pythran passes did declare
dependencies to analyse that were not used. Removing this dependencies avoids
some extra computation!

See commits `6c9f5630f4 <https://github.com/serge-sans-paille/pythran/commit/6c9f5630f406ec178a62eddb302445d5057c0557>`_ and `b8a8a11e22 <https://github.com/serge-sans-paille/pythran/commit/b8a8a11e2216cafa1bebdf0a029b1adbd27d6179>`_.

Use __slots__
-------------

The `Binds To <../2016-04-18-aliasing-improved.rst>`_ analysis is
relatively costly in some cases, as it (roughly) creates a tiny object for many
AST nodes. The associated class now uses ``__slots__`` to declare its member,
which speeds up the object creation.

See commit `39c8c3bdd4 <https://github.com/serge-sans-paille/pythran/commit/39c8c3bdd4e93c068240adc46fdd723074a3f90f>`_.

Beware of IPython
-----------------

Pythran can be integrated to Jupyter notebooks and to the IPython console
through the use of ``IPython.core.magic``. This used to be imported by default
in the Pythran package, which slows down the startup process because the
dependency is huge. It's now still available, but one needs to explicitly
import ``pythran.magic``.

See commit `1e6c7b3a5f <https://github.com/serge-sans-paille/pythran/commit/1e6c7b3a5fcd0004224dcb991740b5444e70e805>`_.

Boost your Compilation Time
---------------------------

Reinventing the wheel is generally not a good thing, so the C++ runtime of
Pythran, ``pythonic`` had some dependencies on `boost
<http://www.boost.org/>`_. We got rid on ``Boost.Python`` a while ago because
of the compilation time overhead, we now got rid of ``Boost.UnorderedMap``
(``std::unordered_map`` is generally ok, even if running slower on some
benchmarks). We keep the dependency on ``Boost.Format`` but limit it to some
header files that are only included for the ``%`` operator of ``str``.

Oh, and include ``<ostream>`` instead of ``<iostream>`` when input is not needed is also a good idea!

See commits `88a16dc631 <https://github.com/serge-sans-paille/pythran/commit/88a16dc631ff1481051e3a721b679a71b74b20e5>`_, `1489f799a4 <https://github.com/serge-sans-paille/pythran/commit/1489f799a42a3b07f295a8e671be441a4e84e443>`_ and `15e1fbaaa8 <https://github.com/serge-sans-paille/pythran/commit/15e1fbaaa801721ac0b9a28c62d24afd1a8a93db>`_.

Constant Fold Wisely
--------------------

Pythran implements a very generic constant folding pass that basically goes
through each node of the AST, check if it's a constant node and if so evaluate
the expression and put the result in the AST in place of the original
expression. We did this a lot, even for literals, which was obviously useless.

See commit `fa0b98b3cc <https://github.com/serge-sans-paille/pythran/commit/fa0b98b3cc0b9b5fc42c5d346c73c39196d59628>`_.

Faster Generated Code
=====================

The original motivation of Pythran is speed of the generated code, and speed remains the primary focus. So, what's new?

Avoid the Leaks
---------------

Memory management in ``pythonic`` is delegated to a shared reference counter,
which is generally ok. We still need some manual managements at the boundaries,
when memory gets allocated by a third-part library, or when it comes from a
``PyObject``. In the latter case, we keep a reference on the original
``PyObject`` and when ``pythonic`` shared reference dies, we decrease the
``PyObject`` reference counter.

When the memory comes from a third-part library, we have a bunch of ways to
state what to do when the reference dies, but this was not part of the
constructor API. And then comes this ``numpy.zeros`` implementation that makes
a call to ``calloc`` but forgets to set the proper destructor. Everything is
now part of the constructor API, which prevents such stupid mistakes. And
**Yes** I really feel ashamed of this one; *really*; **reaalyyyyyy**.

See commit `f294143ca4 <https://github.com/serge-sans-paille/pythran/commit/f294143ca440c788c76af2e3e1f73bc3c439a895>`_.

Lazy numpy.where
----------------

Consider the following Numpy expression:

.. code:: python

    a = numpy.where(a > 1, a ** 2, a + 2)

Python evaluates the three operands before calling ``numpy.where``, which
creates three temporary arrays, and runs the computation of ``**2`` and ``+ 2``
for each element of the array, while these computations are only needed
depending on the value of ``a > 1``. What we need here is lazy evaluation of
the operands, something that was not part of our expression template engine and
is now built-in!

Said otherwise, the previous entry point for an expression template was

.. code::

    template<class T0, class T1, class T2>
    auto operator()(T0 const& arg0, T0 const& arg1, T2 const& arg2) {
      // every argument is evaluated at that point
      return arg0 ? arg1 : arg2;
    }

And it can now be

.. code::

    template<class T0, class T1, class T2>
    auto operator()(T0 const& iter0, T0 const& iter1, T2 const& iter2) {
      // no argument is evaluated at that point, dereferencing triggers the computation
      return *arg0 ? *arg1 : *arg2; /**/
    }

See commit `757795fdc9 <https://github.com/serge-sans-paille/pythran/commit/757795fdc91a2cfafd2e6c8af75a6eb2f64a5db1>`_.

Update Operator
---------------

For some internal operations, I've been lazy and implemented update operator like this:

.. code::

    template<class T>
    auto operator+=(T const& val) {
        return (*this) = (*this) + val;
    } /**/

Being lazy rarely pays off, the extra object created had a performance impact
on 3D data structures, everything is now done properly using in-place
computations.

See commit `2b151e8ec5 <https://github.com/serge-sans-paille/pythran/commit/2b151e8ec501a8cdf10c9543befd2de7e81d4c52>`_.

Range and Python3
-----------------

Python3 support is still experimental in Pythran, as showcased by this bug...
In the backend code, when translating Pythran IR to C++, we have a special case
for plain old loops. Basically if we meet a for loop iterating over an
``xrange`` object, we generate a plain old C loop, even if our ``xrange``
implementation is very light, it pleases the C++ compiler to find this kind of
pattern. Yes, ``xrange``, see the issue? We know correctly lower ``range``
loops from Python3, but there's probably plenty of such details hanging around
:-/

See commit `0f5f10c62f <https://github.com/serge-sans-paille/pythran/commit/0f5f10c62fd35a7ddbc6bd2d699a4ed59592c35b>`_.

Avoid the Div
-------------

At the assembly level, performing an integer division is generally costly, much more than a multiplication.

So instead of doing:

.. code:: c++

    size_t nbiter = size0 / size1;
    for (size_t i = 0; i < nbiter; ++i) {
       ...
    }

Doing (it's not generally equivalent, but in our context it is because ``size0`` is a multiple of ``size1``)

.. code:: c++

    for (size_t i = 0; i < size0; i += size1) {
       ...
    }

Is generally faster.

See commit `79293c9378 <https://github.com/serge-sans-paille/pythran/commit/79293c937869082e97409c68db5ecfd4b8540315>`_.


Transposed Array
----------------

Even at the C API level, Numpy array have the notion of data layout built-in,
to cope with FORTRAN-style and C-style memory layout. This is used as a trick
to get transposition for free, but we did not implement this when converting
transposed array from C++ to Python, which led in a costly and useless
computation. Setting the proper flag did the job.

See commit `6f27ac3916 <https://github.com/serge-sans-paille/pythran/commit/6f27ac391675b2941988cfcce1ab25819cecdc70>`_.

Avoid usless conversions
------------------------

In C++ (and C) when one adds a ``uint8`` with a ``uint8``, he ends up with an
``int``. This is not the default behavior of numpy arrays, so we did hit a bug
here. I still think that delegating type inference to C++ was a good choice,
because the C++ implementation automatically documents and provides the
function type without the need of manually filling each function type
description has we did for the type checker, but it still requires some care.

See commit `fae8ba1bbc <https://github.com/serge-sans-paille/pythran/commit/fae8ba1bbc92ac3a9e610d1eb9d1eb76f09f5fa0>`_.

Conclusion
==========

Pythran did improve a lot thanks to the OpenDreamKit project, I cannot find ways to thank them enough for their trust. I'm also in debt to `Logilab <https://www.logilab.fr/>`_, for their help thoughout the whole project.

As usual, I'm in debt to `Lancelot Six <https://github.com/lsix>`_ for his careful review of this post.

Finally, I'd like to thank `Yann Diorcet <https://github.com/diorcety>`_, `Ashwin Vishnu <https://github.com/ashwinvis>`_ and `Adrien Guinet <https://github.com/aguinet>`_ for stepping into the Pythran codebase and providing useful bug reports *and* commits!

