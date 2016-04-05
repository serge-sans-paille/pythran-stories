Compiler Flags
##############

:date: 2016-04-05
:category: benchmark
:lang: en
:authors: Lightjohn
:summary: Let's re-run an existing benchmark with pythran 

The benchmark
=============

First there was a paper [0]_, 
in the paper there was a github [1]_, 
in the github [1]_ some benchmarks. 
In my case I wanted to re-run the julia code because the language is changing quickly and so may do better now. 
But the day before I discovered `Pythran` so why not test both?

And so let's re-run two benchmarks: `C++ <https://github.com/jesusfv/Comparison-Programming-Languages-Economics/blob/master/RBC_CPP.cpp>`_ , `Julia <https://github.com/jesusfv/Comparison-Programming-Languages-Economics/blob/master/RBC_Julia.jl>`_ and add a new one, Pythran.

C++ results
-----------

Compiling and running C++ code was easy:

.. code:: sh

	% g++ -Ofast RBC_CPP.cpp -o testcpp


then


.. code:: julia

	% ./testcpp 
	Output = 0.562731, Capital = 0.178198, Consumption = 0.384533
	Iteration = 1, Sup Diff = 0.0527416
	Iteration = 10, Sup Diff = 0.0313469
	Iteration = 20, Sup Diff = 0.0187035
	[...]
	Iteration = 230, Sup Diff = 3.87636e-07
	Iteration = 240, Sup Diff = 2.32197e-07
	Iteration = 250, Sup Diff = 1.39087e-07
	Iteration = 257, Sup Diff = 9.71604e-08
	 
	My check = 0.146549 
	Elapsed time is   = 2.40271


Julia results
-------------

Then Julia Code:

we run `julia`:

.. code:: julia

	include("RBC_Julia.jl")
	julia> @time main()
	Output = 0.5627314338711378 Capital = 0.178198287392527 Consumption = 0.3845331464786108
	Iteration = 1 Sup Diff = 0.05274159340733661
	Iteration = 10 Sup Diff = 0.031346949265852075
	Iteration = 20 Sup Diff = 0.01870345989335709
	[...]
	Iteration = 230 Sup Diff = 3.876361940324813e-7
	Iteration = 240 Sup Diff = 2.3219657929729465e-7
	Iteration = 250 Sup Diff = 1.3908720952748865e-7
	Iteration = 257 Sup Diff = 9.716035642703957e-8
	 
	My check = 0.1465491436962635
	3.001183 seconds (3.84 k allocations: 703.276 MB, 0.68% gc time)

Not bad!

Python: pythran  and numba
--------------------------

Now some pythran code, we use the numba version as starter: so we remove numba decorator and 
replace it by a pythran comment:

.. code:: python

	from numba import autojit
	
	@autojit
	def innerloop(bbeta, nGridCapital, gridCapitalNextPeriod, mOutput, nProductivity, vGridCapital, expectedValueFunction, mValueFunction, mValueFunctionNew, mPolicyFunction):

to

.. code:: python

	#pythran export innerloop(float, int, int, float[][], int, float[], float[][], float[][], float[][], float[][])
  
	def innerloop(bbeta, nGridCapital, gridCapitalNextPeriod, mOutput, nProductivity, vGridCapital, expectedValueFunction, mValueFunction, mValueFunctionNew, mPolicyFunction):


Easy? not quite... while pythranisation of the code, something went wrong, but
no idea why ! With some (many) help, the solution was found: the idea was to extract the innerloop into a 
new file and run pythran on it then calling it from the main code.

The function is in `je.py` and the main code is `run_je.py`

Let's run the code:

.. code:: sh

	% time python2 run_je.py 
	Output =  0.562731433871  Capital =  0.178198287393  Consumption =  0.384533146479
	Iteration =  1 , Sup Diff =  0.0527415934073
	Iteration =  10 , Sup Diff =  0.0313469492659
	Iteration =  20 , Sup Diff =  0.0187034598934
	[...]
	Iteration =  230 , Sup Diff =  3.87636194032e-07
	Iteration =  240 , Sup Diff =  2.32196579297e-07
	Iteration =  250 , Sup Diff =  1.39087209527e-07
	python2 run_je.py  2,45s user 0,08s system 94% cpu 2,666 total

And it is very nice!

And just for fun `python numba <https://github.com/jesusfv/Comparison-Programming-Languages-Economics/blob/master/RBC_Python_Numba.py>`_:

.. code:: sh

	% time python2 RBC_Python_Numba.py 
	Output =  0.562731433871  Capital =  0.178198287393  Consumption =  0.384533146479
	Iteration =  1 , Sup Diff =  0.0527415934073
	Iteration =  10 , Sup Diff =  0.0313469492659
	Iteration =  20 , Sup Diff =  0.0187034598934
	[...]
	Iteration =  230 , Sup Diff =  3.87636194032e-07
	Iteration =  240 , Sup Diff =  2.32196579297e-07
	Iteration =  250 , Sup Diff =  1.39087209527e-07
	Iteration =  257 , Sup Duff =  9.71603566491e-08
 
	My Check =  0.146549143696
	Elapse time = is  3.00302290916

So what do we have: 

**C++: 2.4 sec**

**Pythran: 2.4 sec**

**Numba: 3 sec**

**Julia: 3 sec**

These benchs were run on a modest Pentium R 3550M @ 2.3GHz

But what amaze me was the fact that with `pythran` we were able to close my high-end Intel i7
machine.

Conclusion
----------

To conclude, pythran is for me still young, like julia, but for a little cost and no particular knowlegde you can
get the same performances as C code in Python. It worth the time to take a look to pythran.

So good luck Pythran!

.. [0] http://economics.sas.upenn.edu/~jesusfv/comparison_languages.pdf

.. [1] https://github.com/jesusfv/Comparison-Programming-Languages-Economics
