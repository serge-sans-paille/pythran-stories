Compiler Flags
##############

:date: 2016-04-05
:category: benchmark
:lang: en
:authors: Lightjohn
:summary: Let's re-run an existing benchmark with pythran 

The benchmark
=================

First there was a paper [0]_, 
in the paper there was a github [1]_, 
in the github [1]_ some benchmarks. 
In my case I wanted to re-run the julia code because the language is changing quickly and so may do better. 
But the day before I discovered `Pythran` so why not test both ?

And so let's re-run two benchmarks: C++, Julia and add a new one, Pythran.

Compiling and running C++ code was easy:

	g++ -Ofast RBC_CPP.cpp -o testcpp


then

	testcpp 
	Output = 0.562731, Capital = 0.178198, Consumption = 0.384533
	Iteration = 1, Sup Diff = 0.0527416
	Iteration = 10, Sup Diff = 0.0313469
	Iteration = 20, Sup Diff = 0.0187035
	Iteration = 30, Sup Diff = 0.0111655
	Iteration = 40, Sup Diff = 0.00666854
	Iteration = 50, Sup Diff = 0.00398429
	Iteration = 60, Sup Diff = 0.00238131
	Iteration = 70, Sup Diff = 0.00142366
	Iteration = 80, Sup Diff = 0.00085134
	Iteration = 90, Sup Diff = 0.000509205
	Iteration = 100, Sup Diff = 0.000304623
	Iteration = 110, Sup Diff = 0.000182265
	Iteration = 120, Sup Diff = 0.00010907
	Iteration = 130, Sup Diff = 6.52764e-05
	Iteration = 140, Sup Diff = 3.90711e-05
	Iteration = 150, Sup Diff = 2.33881e-05
	Iteration = 160, Sup Diff = 1.40086e-05
	Iteration = 170, Sup Diff = 8.39132e-06
	Iteration = 180, Sup Diff = 5.02647e-06
	Iteration = 190, Sup Diff = 3.0109e-06
	Iteration = 200, Sup Diff = 1.80355e-06
	Iteration = 210, Sup Diff = 1.08034e-06
	Iteration = 220, Sup Diff = 6.47132e-07
	Iteration = 230, Sup Diff = 3.87636e-07
	Iteration = 240, Sup Diff = 2.32197e-07
	Iteration = 250, Sup Diff = 1.39087e-07
	Iteration = 257, Sup Diff = 9.71604e-08
	 
	My check = 0.146549
	 
	Elapsed time is   = 2.40271


Then Julia Code:

we run `julia`:


	include("RBC_Julia.jl")
	julia> @time main()
	Output = 0.5627314338711378 Capital = 0.178198287392527 Consumption = 0.3845331464786108
	Iteration = 1 Sup Diff = 0.05274159340733661
	Iteration = 10 Sup Diff = 0.031346949265852075
	Iteration = 20 Sup Diff = 0.01870345989335709
	Iteration = 30 Sup Diff = 0.01116551203397087
	Iteration = 40 Sup Diff = 0.006668541708132691
	Iteration = 50 Sup Diff = 0.003984292748717033
	Iteration = 60 Sup Diff = 0.0023813118039327508
	Iteration = 70 Sup Diff = 0.0014236586450983024
	Iteration = 80 Sup Diff = 0.0008513397747206275
	Iteration = 90 Sup Diff = 0.0005092051752288995
	Iteration = 100 Sup Diff = 0.0003046232442147634
	Iteration = 110 Sup Diff = 0.00018226485632300005
	Iteration = 120 Sup Diff = 0.00010906950872635601
	Iteration = 130 Sup Diff = 6.527643736320421e-5
	Iteration = 140 Sup Diff = 3.907108211997912e-5
	Iteration = 150 Sup Diff = 2.3388077119990136e-5
	Iteration = 160 Sup Diff = 1.4008644637408807e-5
	Iteration = 170 Sup Diff = 8.391317203093607e-6
	Iteration = 180 Sup Diff = 5.0264745379280384e-6
	Iteration = 190 Sup Diff = 3.010899863764571e-6
	Iteration = 200 Sup Diff = 1.8035522481030242e-6
	Iteration = 210 Sup Diff = 1.0803409160597965e-6
	Iteration = 220 Sup Diff = 6.471316946754513e-7
	Iteration = 230 Sup Diff = 3.876361940324813e-7
	Iteration = 240 Sup Diff = 2.3219657929729465e-7
	Iteration = 250 Sup Diff = 1.3908720952748865e-7
	Iteration = 257 Sup Diff = 9.716035642703957e-8
	 
	My check = 0.1465491436962635
	3.001183 seconds (3.84 k allocations: 703.276 MB, 0.68% gc time)

Not bad !

Now some pythran code, we use the numba version: so we remove numba import and 
add the pythran decorator:


	from numba import autojit
	
	@autojit
	def innerloop(bbeta, nGridCapital, gridCapitalNextPeriod, mOutput, nProductivity, vGridCapital, expectedValueFunction, mValueFunction, mValueFunctionNew, mPolicyFunction):

to

	#pythran export innerloop(float, int, int, float[][], int, float[], float[][], float[][], float[][], float[][])
	  
	def innerloop(bbeta, nGridCapital, gridCapitalNextPeriod, mOutput, nProductivity, vGridCapital, expectedValueFunction, mValueFunction, mValueFunctionNew, mPolicyFunction):


Easy ? not quite... while pythranisation of the code, something went wrong, but
no idea why ! With some (many) help the idea was to extract the innerloop into a 
new file and run pythran on it then calling it from the main code.

The function is in `je.py` and the main code is `run_je.py`

Let's run the code:


	time python2 run_je.py 
	Output =  0.562731433871  Capital =  0.178198287393  Consumption =  0.384533146479
	Iteration =  1 , Sup Diff =  0.0527415934073
	Iteration =  10 , Sup Diff =  0.0313469492659
	Iteration =  20 , Sup Diff =  0.0187034598934
	Iteration =  30 , Sup Diff =  0.011165512034
	Iteration =  40 , Sup Diff =  0.00666854170813
	Iteration =  50 , Sup Diff =  0.00398429274872
	Iteration =  60 , Sup Diff =  0.00238131180393
	Iteration =  70 , Sup Diff =  0.0014236586451
	Iteration =  80 , Sup Diff =  0.000851339774721
	Iteration =  90 , Sup Diff =  0.000509205175229
	Iteration =  100 , Sup Diff =  0.000304623244215
	Iteration =  110 , Sup Diff =  0.000182264856323
	Iteration =  120 , Sup Diff =  0.000109069508726
	Iteration =  130 , Sup Diff =  6.52764373631e-05
	Iteration =  140 , Sup Diff =  3.907108212e-05
	Iteration =  150 , Sup Diff =  2.33880771201e-05
	Iteration =  160 , Sup Diff =  1.40086446374e-05
	Iteration =  170 , Sup Diff =  8.39131720298e-06
	Iteration =  180 , Sup Diff =  5.02647453804e-06
	Iteration =  190 , Sup Diff =  3.01089986388e-06
	Iteration =  200 , Sup Diff =  1.8035522481e-06
	Iteration =  210 , Sup Diff =  1.08034091595e-06
	Iteration =  220 , Sup Diff =  6.47131694453e-07
	Iteration =  230 , Sup Diff =  3.87636194032e-07
	Iteration =  240 , Sup Diff =  2.32196579297e-07
	Iteration =  250 , Sup Diff =  1.39087209527e-07
	python2 run_je.py  2,45s user 0,08s system 94% cpu 2,666 total

And it is very nice !

So what do we have: 

**C++: 2.4 sec**

**Pythran: 2.4 sec**

**Julia: 3 sec**

These benchs were run on a modest Pentium R 3550M @ 2.3GHz

Partial benchs (only C++ and Julia) were run on i7-2600 @ 3.40GHz for results quite 
similar in time but Julia was doing better:

**C++: 2.0 sec**

**Julia: 1.8 sec**

But what amaze me was the fact that with pythran we were able to close an high-end 
machine.

So good luck Pythran !

.. [0] http://economics.sas.upenn.edu/~jesusfv/comparison_languages.pdf

.. [1] https://github.com/jesusfv/Comparison-Programming-Languages-Economics
