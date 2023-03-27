xsimd - again
#############

:date: 2021-05-13
:category: engineering
:lang: en
:authors: serge-sans-paille
:summary: Not stricly a post about Pythran, but about one of its component:
          xsimd, the vectorization engine we (optionally) use. And more specifically about
          a new forthcoming feature of it: dispatching call based on supported instruction set.

*Note: I'm publishing this article the 26th of March, 2023, because… I forgot to
do this when I wrote it some two years ago :-)*


`xsimd <https://xsimd.readthedocs.io>`_ is a header-only C++11 library that
provides an efficient abstraction for Single Instruction Multiple Data (SIMD)
programming based on the vector instruction sets available in commodity
hardware: SSE, AVX, Neon etc.

Many such libraries exist: `boost.simd
<https://github.com/NumScale/boost.simd>`_ from which ``xsimd`` got originallay
derived, `MIPP <https://github.com/aff3ct/MIPP>`_ from the academia, `eve
<https://github.com/aff3ct/MIPP>`_ developped by Joel Flacou in C++20, `std-simd
<https://github.com/VcDevel/std-simd>`_ which implements *ISO/IEC TS 19570:2018
Section 9 "Data-Parallel Types"* or `simdpp
<https://github.com/p12tic/libsimdpp>`_ that supports Intel, ARM, PowerPC and
MIPP targets.

Each library support different combination of API, architecture and utilities,
but the goal of this post is not to discuss the merti of each, just to showcase
one approach that at least ``simdpp`` supports and that wasn't available in
``xsimd``.

The Problem
===========

Let's consider the following code, that performs a school-book mean between two
vectors:

.. code-block:: c++

    void mean(const std:vector<double>& a, const std::vector<double>& b, std::vector<double>& res)
    {
        std::size_t size = res.size();
        for(std::size_t i = 0; i < size; ++i)
        {
            res[i] = (a[i] + b[i]) / 2;
        }
    }

According to the documentation, the ``xsimd`` implementation would be:

.. code-block:: c++

    void mean(const std::vector<double>& a, const std::vector<double>& b, std::vector<double>& res)
    {
        using b_type = xsimd::simd_type<double>;
        std::size_t inc = b_type::size;
        std::size_t size = res.size();
        // size for which the vectorization is possible
        std::size_t vec_size = size - size % inc;
        for(std::size_t i = 0; i < vec_size; i += inc)
        {
            b_type avec = xsimd::load_unaligned(&a[i]);
            b_type bvec = xsimd::load_unaligned(&b[i]);
            b_type rvec = (avec + bvec) / 2;
            xsimd::store_unaligned(&res[i], rvec);
        }
        // Remaining part that cannot be vectorize
        for(std::size_t i = vec_size; i < size; ++i)
        {
            res[i] = (a[i] + b[i]) / 2;
        }
    }

When compiling this kernel, one need to pass specific architecture flags to tell
the compiler which architecture is targeted, e.g. ``-mavx`` to tell the compiler
the machine this code is compiled for supports AVX. In turns, ``xsimd`` picks
that architecture and the generic code above actually turns into AVX-specific
code.

A problem arise when the target architecture details are not known, for instance
when distributing a compiled program in the wild: is AVX2 available? SSE4? One
option is to set minimal requirements, but that means not taking advantage of
the target actual full potential.

The (well-known) solution is to generate one version of the code per
architecture we want to support, and let a *runtime dispatcher* inspect at
runtime which version to pick.


Dispatching Vectorized Kernel
=============================

Let's take advantage of a new feature of ``xsimd`` that makes it possible to
explicitely state the architecture we want to support:

.. code-block:: c++

    struct mean
    {
        template<typename Arch>
        void operator()(Arch, const std::vector<double>& a, const std::vector<double>& b, std::vector<double>& res)
        {
            // this is the only changing line
            using b_type = xsimd::arch::batch<double, Arch>;

            std::size_t inc = b_type::size;
            std::size_t size = res.size();
            std::size_t vec_size = size - size % inc;
            for(std::size_t i = 0; i < vec_size; i += inc)
            {
                b_type avec = xsimd::load_unaligned(&a[i]);
                b_type bvec = xsimd::load_unaligned(&b[i]);
                b_type rvec = (avec + bvec) / 2;
                xsimd::store_unaligned(&res[i], rvec);
            }
            for(std::size_t i = vec_size; i < size; ++i)
            {
                res[i] = (a[i] + b[i]) / 2;
            }
        }
    };

By making the target architecture explicit through a template parameter, it is
possible to generate different version of the code, one per target architecture,
while still maintaining a single version of the code.

``xsimd`` now also provides a utility function to create a dispatcher from a
functor as the one above (that's why we're using a functor, remember ``xsimd``
supports C++11, so no ``auto`` lambda magic ;-):

.. code-block:: c++

    using archs = xsimd::arch_list<xsimd::avx2, xsimd::sse2>;
    auto generic_mean = xsimd::arch::dispatch<archs>(mean{});

``generic_mean`` can be called as the original ``mean`` function, without
speicifying the ``Arch`` argument. Internally, it performs a runtime dispatch
depending on the target it's running on. From a developper point of view, one
needs to specify all targeted platforms at compile-time, say ``-msse4 -mavx2
-mavx512``, all three versions of the code will be compiled in the final binary,
but only the relevant one gets executed (thank you, no ``SIGILL``).

This is now all documented in
https://xsimd.readthedocs.io/en/latest/api/dispatching.html!


Conclusion
==========

Dispatching based on the running platform is not new. The ELF format even has an
extension to support this pattern through `ifunc
<https://gcc.gnu.org/onlinedocs/gcc-4.7.2/gcc/Function-Attributes.html#index-g_t_0040code_007bifunc_007d-attribute-2529>`_.
Nevertheless it was fun to implement and that's a great addition to ``xsimd``!
Now I need to think about integrating that in Pythran ;-)

Acknoledgments
==============

Thanks a lot to Johan Mabille for the reviews, the jokes and the chatting (in no
particular order).

Special thanks to Joël Flacou for inspiring this work in so many ways.
