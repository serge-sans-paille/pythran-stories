GSoC’21 Improve performance through the use of Pythran
######################################################

:date: 2021-08-19
:category: examples
:lang: en
:authors: Xingyu Liu
:summary: This project is about using Pythran to accelerate algorithms in SciPy and 
          writing benchmarks for the algorithms. Let's look into the details of the project.



Project Overview
================
There are a lot of algorithms in `SciPy <https://github.com/scipy/scipy>`_ that use `Cython <https://github.com/cython/cython>`_ to improve 
the performance of code that would be too slow as pure Python, 
e.g. algorithms in ``scipy.spatial``, ``scipy.stats`` and ``scipy.optimize``. 
Recently, SciPy added experimental support for `Pythran <https://github.com/serge-sans-paille/pythran>`_, 
to make it easier to accelerate Python code. 
Compared with Cython, Pythran is more readable and even faster. 
Furthermore, SciPy uses `Airspeed Velocity <https://asv.readthedocs.io/>`_ for performance benchmarking. 
Therefore, our project includes:


* Writing benchmarks for the algorithms in SciPy
* Accelerating SciPy algorithms with Pythran.
* Find and solve potential issues in Pythran


My full proposal can be accessed `here <https://docs.google.com/document/d/1nM7dYbmModiukQw-sSOVGz6t5S6HC0VVWucYadI_aMQ/edit?usp=sharing>`_.


What I have done
================

Pull Requests
-------------

**SciPy**

In SciPy, I mainly worked on writing benchmarks to measure the performance
of algorithms and using Pythran to accelerate those algorithms. Also, I 
looked into the public open issues now and then and helped fix them.

#. |SciPy| |benchmark| |Merged| `BENCH: add benchmark for f_oneway <https://github.com/scipy/scipy/pull/14018>`_
#. |SciPy| |benchmark| |Merged| `BENCH: add benchmark for energy_distance and wasserstein_distance <https://github.com/scipy/scipy/pull/14163>`_
#. |SciPy| |benchmark| |Merged| `BENCH: add more benchmarks for inferential statistics tests <https://github.com/scipy/scipy/pull/14228#>`_
#. |SciPy| |benchmark| |Merged| `MAINT: Modify to use new random API in benchmarks <https://github.com/scipy/scipy/pull/14224#>`_: Most of current benchmarks uses ``np.random.seed()``, but it is recommended to use ``np.random.default_rng()`` instead.
#. |SciPy| |benchmark| |Merged| `BENCH: add benchmark for somersd <https://github.com/scipy/scipy>`_

#. |SciPy| |accelerate| |Merged| `ENH: use Pythran to speedup somersd and _tau_b <https://github.com/scipy/scipy/pull/14308>`_
#. |SciPy| |bug| |Merged| `DOC: clarify meaning of rvalue in stats.linregress <https://github.com/scipy/scipy/pull/14458>`_ : helped fix a bug and review the PR.
#. |SciPy| |bug| |Under Review| `BUG: fix stats.binned_statistic_dd issue with values close to bin edge <https://github.com/scipy/scipy/pull/14338>`_ : helped fix a bug.

#. |SciPy| |accelerate| |Under Review| `ENH: Pythran implementation of _compute_prob_outside_square and _compute_prob_inside_method to speedup stats.ks_2samp <https://github.com/scipy/scipy/pull/13957>`_
#. |SciPy| |accelerate| |Under Review| `ENH: improved binned_statistic_dd via Pythran <https://github.com/scipy/scipy/pull/14345>`_ 
#. |SciPy| |accelerate| |Under Review| `ENH: improve cspline1d, qspline1d, and relative funcs via Pythran <https://github.com/scipy/scipy/pull/14429>`_ 
#. |SciPy| |accelerate| |Under Review| `ENH: improve siegelslopes via pythran <https://github.com/scipy/scipy/pull/14430>`_ 

#. |SciPy| |accelerate| |On Hold| `ENH: Pythran implementation of _cdf_distance <https://github.com/scipy/scipy/pull/14154>`_ : Pythran version is slightly better than the Python one after fixing ``np.searchsorted()``. When SciPy begin using SIMD in the future, it may be faster so this PR is currently on hold.
#. |SciPy| |accelerate| |On Hold| `WIP: ENH: improve _count_paths_outside_method via pythran <https://github.com/scipy/scipy/pull/14314>`_ : This PR got stuck in a Mac specific error and we haven’t find out why.
#. |SciPy| |accelerate| |On Hold| `WIP: ENH: improve sort_vertices_of_regions via Pythran and made it more readable <https://github.com/scipy/scipy/pull/14376>`_ : There are currently two tests we can’t pass because 1. With Pythran we can’t do inplace sort 2. The input type will change in the Pythran function
#. |SciPy| |accelerate| |Closed| `ENH: improve _sosfilt_float via Pythran <https://github.com/scipy/scipy/pull/14473>`_  : ``_sosfilt_float`` is already implemented in Cython. We were considering to replace it but found Pythran performance is not much better than Cython's, and Pythran does not support ``object`` type, so we decided not to merge it.


**Pythran**

When using Pythran to improve SciPy algorithms, I found some important modules are not 
supported or got false result in Pythran currently, e.g. boolean arguments 
such as ``keepdims`` were not supported in Pythran because the return type
would change based on the value of ``keepdims`` (True or False). Therefore, I made a general
support for such cases.


#. |Pythran| |feature| |Merged| `Import test cases from scipy <https://github.com/serge-sans-paille/pythran/pull/1830>`_ : Import Pythran functions in SciPy as test case in Pythran
#. |Pythran| |feature| |Merged| `Feature/add keep dims <https://github.com/serge-sans-paille/pythran/pull/1869#>`_ : support keepdims argument in ``np.mean()`` in Pythran
#. |Pythran| |feature| |Merged| `Support boolean arguments in numpy unique <https://github.com/serge-sans-paille/pythran/pull/1876>`_
#. |Pythran| |feature| |Merged| `General implementation of supporting immediate arguments <https://github.com/serge-sans-paille/pythran/pull/1878>`_: Generalize the above two solutions to support immediate arguments.


Issues
------

In addition to the above-mentioned issues, I dug up more issues in Pythran while
using it, so I opened many issues in Pythran. My mentors often helped solve 
those issues and then I tested whether the fixes worked. 


#. |Closed| `Pythran makes np.searchsorted much slower <https://github.com/serge-sans-paille/pythran/issues/1793>`_ 
#. |Closed| `Pythran may make a function slower? <https://github.com/serge-sans-paille/pythran/issues/1753>`_ 
#. |Closed| `u_values[u_sorter].searchsort would cause "Function path is chained attributes and name" but np.search would not <https://github.com/serge-sans-paille/pythran/issues/1792>`_
#. |Closed| `all_values.sort() would cause compilation error but np.sort(all_values) would not <https://github.com/serge-sans-paille/pythran/issues/1791>`_
#. |Closed| `u_values[u_sorter].searchsort would cause "Function path is chained attributes and name" but np.searchsort would not <https://github.com/serge-sans-paille/pythran/issues/1792>`_
#. |Closed| `Support scipy.special.binom? <https://github.com/serge-sans-paille/pythran/issues/1804>`_
#. |Closed| `Got AttributeError: module 'scipy' has no attribute 'special' when building scipy with special import <https://github.com/serge-sans-paille/pythran/issues/1815>`_
#. |Closed| `Got compilation error when the inner variable type changes <https://github.com/serge-sans-paille/pythran/issues/1818>`_
#. |Closed| `Can't index an 2d array like a1[int, tuple] <https://github.com/serge-sans-paille/pythran/issues/1819>`_
#. |Closed| `keep_dims is not supported in np.mean() <https://github.com/serge-sans-paille/pythran/issues/1820>`_
#. |Closed| `can't use np.expand_dims with specified keyword argument <https://github.com/serge-sans-paille/pythran/issues/1850>`_
#. |Open| `bus error on Mac but works fine on Linux for _count_paths_outside_method pythran version <https://github.com/scipy/scipy/issues/14315>`_ 
#. |Open| `array assignment res[cond1] = ax[cond1] works fine for int[] or float[] or float[:,:] but not int[:,:] <https://github.com/serge-sans-paille/pythran/issues/1858>`_

Work Left
=========

As the project proceeded, I found it was difficult to find 
suitable algorithms to be implemented. A suitable algorithm for Pythran should meet at least three requirements:

* It is currently slow. 
* It does not have modules that Pythran doesn't support, e.g. class type, imported SciPy modules.
* It has obvious loops so that the speedup would be large. 

I looked through almost all the algorithms but found little.
Moreover, in our past experience 
with Pythran, we often run into some things that are easy to get wrong, such as 
using arrays that are views as input to a Pythranized function, or the use of different dtypes. 
Therefore, we need better testing and we decided to change the plan to 
write better testing infrastructure for Pythran extensions: 
`WIP: TST: add tests for Pythran somersd <https://github.com/scipy/scipy/pull/14559#>`_


Project Experience
==================
It has been a great experience working on this project in GSoC'21, 
my mentors are really friendly and responsive, 
and the community are also always willing to help. 


Special thanks to my mentors, Ralf and Serge, who provided immense support 
for me to get through the difficulties.
I’m very fortunate to get the chance to dive into and contribute to SciPy 
and Pythran this summer, especially with such awesome mentors. 
I have learnt a lot, both intellectually and spiritually. I would love to continue contributing to SciPy and Pythran in the future :)


Thanks to Google Summer of Code and the Python Software Foundation! 

.. |SciPy| image:: https://img.shields.io/badge/SciPy-1F618D
.. |accelerate| image:: https://img.shields.io/badge/accelerate-A9DFBF
.. |benchmark| image:: https://img.shields.io/badge/benchmark-F9E79F
.. |feature| image:: https://img.shields.io/badge/feature-F5CBA7
.. |Pythran| image:: https://img.shields.io/badge/Pythran-EC7063 
.. |bug| image:: https://img.shields.io/badge/bug-5D6D7E
.. |Merged| image:: https://img.shields.io/badge/Merged-76448A
.. |Closed| image:: https://img.shields.io/badge/Closed-A6ACAF
.. |Open| image:: https://img.shields.io/badge/Open-2ea44f
.. |Under Review| image:: https://img.shields.io/badge/Under Review-2ea44f
.. |On Hold| image:: https://img.shields.io/badge/On Hold-F5B7B1