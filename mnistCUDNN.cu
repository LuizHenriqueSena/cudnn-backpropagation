/**
* Copyright 2016 Abhishek Kumar. All rights reserved.
*
* Please refer to the Abhishek Kumar end user license agreement (EULA) associated
* with this source code for terms and conditions that govern your use of
* this software. Any use, reproduction, disclosure, or distribution of
* this software and related documentation outside the terms of the EULA
* is strictly prohibited.
*
*/

/*
 * This code implements forward propagation and backward propagation on
 * convolutional layer, pooling layer, fully connected layer, activation layer 
 * and softmax layer. This code learns randomly initialzed weights and then 
 * stores them into binary files. The network architecture is generic and hence 
 * this code can be use to create, train and test neural network of any size or
 * depth. Code supports both float and double precision and it saves the weights 
 * accordingly.
 */

/******************************************************************************
 * HEADER FILES
 *****************************************************************************/

// Standard header files for standard functions
#include <sstream>
#include <fstream>
#include <stdlib.h>
#include <vector>
#include <algorithm>
#include <iomanip>
#include <ctime>

#include <cuda.h> 			// CUDA_VERSION
#include <cudnn.h>			// cuDNN routines
#include <cublas_v2.h>		// cublas routines

#include "ImageIO.h"		// FreeImage library for reading jpg images
#include "error_util.h"		// Contains error handling functions

/******************************************************************************
 * MACROS
 *****************************************************************************/

// #define MATRIX_DATA_TYPE_FLOAT
#define MATRIX_DATA_TYPE_DOUBLE		// Use double precision

#ifdef MATRIX_DATA_TYPE_FLOAT
#define MATRIX_DATA_TYPE float
#else
#ifdef MATRIX_DATA_TYPE_DOUBLE
#define MATRIX_DATA_TYPE double
#endif
#endif

#ifndef MATRIX_DATA_TYPE
#error "MATRIX_DATA_TYPE not defined"
#endif

// Handle both precisions in cublas calls
#if defined(MATRIX_DATA_TYPE_FLOAT)
	#define CUBLAS_GEMM cublasSgemm
 	#define CUBLAS_GEAM cublasSgeam
 	#define CUBLAS_GEMV cublasSgemv
 	#define CUBLAS_SCAL cublasSscal
#elif defined(MATRIX_DATA_TYPE_DOUBLE)
	#define CUBLAS_GEMM cublasDgemm
 	#define CUBLAS_GEAM cublasDgeam
 	#define CUBLAS_GEMV cublasDgemv
 	#define CUBLAS_SCAL cublasDscal
#endif

// MSIZE returns the byte size
#define MSIZE(a) ((a)*sizeof(value_type))


// Define Input Dimensions
#define IMAGE_H (28)
#define IMAGE_W (28)
#define IMAGE_D (1)
#define N (IMAGE_D*IMAGE_H*IMAGE_W)  // dimension of training data


// Define 2 args and 3 args max, min functions
#define minn(a,b) (a<b?a:b)
#define maxx(a,b) (a>b?a:b)
#define minnn(a,b,c) (minn(minn(a,b),c))
#define maxxx(a,b,c) (maxx(maxx(a,b),c))

// Define logging functions
//#define print(a) (std::cout<<std::setprecision(0)<<std::fixed<<a)
#define print(a) (std::cout<<std::fixed<<a)
#define println(a) (print(a<<std::endl<<std::flush))

#define DEBUG (0)
//#define VERBOSE (0)

#ifdef VERBOSE
	#define vprint(a) print(a)
	#define vprintln(a) println(a)
#else
	#define vprint(a)
	#define vprintln(a)
#endif

#ifdef DEBUG
	#define dprint(a) print(a)
	#define dprintln(a) println(a)
#else
	#define dprint(a)
	#define dprintln(a)
#endif

#define EXIT_WAIVED 0

/******************************************************************************
 * CONSTANTS AND GLOBALS
 *****************************************************************************/

// save and load weights from this path
const std::string weights_folder = "bins/";

// global learning rate which decreases with epochs
double learning_rate;

#define LENET

#ifndef LENET
 	#define FFNET 100
#endif


#ifdef LENET
 	#define BASE_GAMMA (0.001)
 	
 	#define NETWORK_ARCH			\
 		Layer_t<value_type> conv1; 	conv1.initConvLayer("conv1", 1, 20, 5, 1, IMAGE_H, IMAGE_W, 0, batch_size);	\
		Layer_t<value_type> pool1; 	pool1.initPoolLayer("pool1", 2, 2, conv1, 		batch_size);				\
		Layer_t<value_type> conv2; 	conv2.initConvLayer("conv2", pool1.kernel_dim, 50, 5, 1, pool1.out_width, pool1.out_height, pool1.outputs, batch_size);		\
		Layer_t<value_type> pool2; 	pool2.initPoolLayer("pool2", 2, 2, conv2, 		batch_size);				\
		Layer_t<value_type> fc1;	fc1.initFCLayer    ("fc1", pool2.outputs, 500, 	batch_size);				\
		Layer_t<value_type> fc1act; fc1act.initActLayer("fc1act", fc1.outputs, 		batch_size);				\
		Layer_t<value_type> fc2; 	fc2.initFCLayer    ("fc2", fc1act.outputs, 10, 	batch_size);				\
		Layer_t<value_type> fc2act; fc2act.initActLayer("fc2act", fc2.outputs, 		batch_size);				\
	
	#define LOAD_DATA (conv1.load() && conv2.load() && fc1.load() && fc2.load())

	#define SAVE_DATA (conv1.save() && conv2.save() && fc1.save() && fc2.save())

	#define COPY_DATA_TO_DEVICE		\
		conv1.copyDataToDevice();	\
		conv2.copyDataToDevice();	\
		fc1.copyDataToDevice();		\
		fc2.copyDataToDevice();		\

	#define COPY_DATA_TO_HOST		\
		conv1.copyDataToHost();		\
		conv2.copyDataToHost();		\
		fc1.copyDataToHost();		\
		fc2.copyDataToHost();		\

	#define LAYER_NAMES 			\
		conv1, pool1, conv2, pool2, fc1, fc1act, fc2, fc2act

	#define LAYER_NAMES_WITH_TYPE	\
		Layer_t<value_type>& conv1,	\
		Layer_t<value_type>& pool1,	\
		Layer_t<value_type>& conv2,	\
		Layer_t<value_type>& pool2,	\
		Layer_t<value_type>& fc1,	\
		Layer_t<value_type>& fc1act,\
		Layer_t<value_type>& fc2,	\
		Layer_t<value_type>& fc2act	\
		
#endif
 	


#ifdef FFNET
 	#define BASE_GAMMA (0.0001)
	
	#define NETWORK_ARCH			\
		Layer_t<value_type> fc1;	fc1.initFCLayer(	"fc1", 		N, 			FFNET, 	batch_size);			\
		Layer_t<value_type> fc1act; fc1act.initActLayer("fc1act", 	fc1.outputs, 		batch_size);			\
		Layer_t<value_type> fc2; 	fc2.initFCLayer(	"fc2", 		fc1act.outputs, 10, batch_size);			\
		Layer_t<value_type> fc2act; fc2act.initActLayer("fc2act", 	fc2.outputs, 		batch_size);			\

	#define LOAD_DATA (fc1.load() && fc2.load())

	#define SAVE_DATA (fc1.save() && fc2.save())

	#define COPY_DATA_TO_DEVICE		\
		fc1.copyDataToDevice();		\
		fc2.copyDataToDevice();		\

	#define COPY_DATA_TO_HOST		\
		fc1.copyDataToHost();		\
		fc2.copyDataToHost();		\


	#define LAYER_NAMES 			\
		fc1, fc1act, fc2, fc2act

	#define LAYER_NAMES_WITH_TYPE	\
		Layer_t<value_type>& fc1,	\
		Layer_t<value_type>& fc1act,\
		Layer_t<value_type>& fc2,	\
		Layer_t<value_type>& fc2act	\


#endif
	
	

/******************************************************************************
 * HELPER FUNCTIONS for classes
 *****************************************************************************/

void get_path(std::string& sFilename, const char *fname, const char *pname)
{
	sFilename = (std::string("datav5/") + std::string(fname));
}

template <typename value_type> 
void printHostVector(std::string str, int size, value_type* vec){
	println(str<<" ("<<size<<") ");
	for (int i = 0; i < minn(size,400); i++)
	{
		print(vec[i] << " ");
	}
	println(" "); 
}

template <typename value_type>
void printDeviceVector(std::string str, int size, value_type* vec_d, int n=1)
{
	for (int i = 0; i < n; ++i)
	{	value_type *vec;
		vec = new value_type[size];
		cudaDeviceSynchronize();
		cudaMemcpy(vec, vec_d+i*size, MSIZE(size), cudaMemcpyDeviceToHost);
		printHostVector(str, size, vec);
		delete [] vec;
	}
}

// IO utils
template <class value_type>
void readBinaryFile(const char* fname, int size, value_type* data_h)
{
	std::ifstream dataFile (fname, std::ios::in | std::ios::binary);
	std::stringstream error_s;
	if (!dataFile)
	{
		error_s << "Error opening file " << fname; 
		FatalError(error_s.str());
	}
	// we assume the data stored is always in float precision
	float* data_tmp = new float[size];
	int size_b = size*sizeof(float);
	if (!dataFile.read ((char*) data_tmp, size_b)) 
	{
		error_s << "Error reading file " << fname; 
		FatalError(error_s.str());
	}

	for (int i = 0; i < size; i++)
	{
		data_h[i] = value_type(data_tmp[i]);
	}
	delete [] data_tmp;
}

template <class value_type>
void readAllocMemcpy(const char* fname, int size, value_type** data_h, value_type** data_d)
{
	*data_h = new value_type[size];

	readBinaryFile<value_type>(fname, size, *data_h);

	int size_b = MSIZE(size);
	checkCudaErrors( cudaMalloc(data_d, size_b) );
	checkCudaErrors( cudaMemcpy(*data_d, *data_h,
								size_b,
								cudaMemcpyHostToDevice) );
}

template <class value_type>
void readImage(const char* fname, value_type* imgData_h)
{
	// declare a host image object for an 8-bit grayscale image
	npp::ImageCPU_8u_C1 oHostSrc;
	std::string sFilename(fname);
	println("Loading image " << sFilename);
	// load gray-scale image from disk
	try
	{
		npp::loadImage(sFilename, oHostSrc);
	}
	catch (npp::Exception &rException)
	{
		FatalError(rException.toString());
	}
	// Plot to console and normalize image to be in range [0,1]
	for (int i = 0; i < IMAGE_H; i++)
	{
		for (int j = 0; j < IMAGE_W; j++)
		{   
			int idx = IMAGE_W*i + j;
			imgData_h[idx] = value_type(*(oHostSrc.data() + idx) / double(255));
		}
	} 
}

template <class value_type>
void printDeviceVector(int size, value_type* vec_d)
{
	value_type *vec;
	vec = new value_type[size];
	cudaDeviceSynchronize();
	cudaMemcpy(vec, vec_d, MSIZE(size), cudaMemcpyDeviceToHost);
	std::cout.precision(5);
	std::cout.setf( std::ios::fixed, std::ios::floatfield );
	for (int i = 0; i < size; i++)
	{
		print(value_type(vec[i]) << " ");
	}
	println(" ");
	delete [] vec;
}

/******************************************************************************
 * demonstrate different ways of setting tensor descriptor
 *****************************************************************************/

//#define SIMPLE_TENSOR_DESCRIPTOR
#define ND_TENSOR_DESCRIPTOR
void setTensorDesc(cudnnTensorDescriptor_t& tensorDesc, 
					cudnnTensorFormat_t& tensorFormat,
					cudnnDataType_t& dataType,
					int n,
					int c,
					int h,
					int w)
{
#if SIMPLE_TENSOR_DESCRIPTOR
	checkCUDNN( cudnnSetTensor4dDescriptor(tensorDesc,
											tensorFormat,
											dataType,
											n, c,
											h,
											w ) );
#elif defined(ND_TENSOR_DESCRIPTOR)
	const int nDims = 4;
	int dimA[nDims] = {n,c,h,w};
	int strideA[nDims] = {c*h*w, h*w, w, 1};
	checkCUDNN( cudnnSetTensorNdDescriptor(tensorDesc,
											dataType,
											4,
											dimA,
											strideA ) ); 
#else
	checkCUDNN( cudnnSetTensor4dDescriptorEx(tensorDesc,
											dataType,
											n, c,
											h, w,
											c*h*w, h*w, w, 1) );
#endif
}

/******************************************************************************
 * Defining Layer Types
 *****************************************************************************/

typedef enum {
		CONV_LAYER	= 0,
		POOL_LAYER	= 1,
		FC_LAYER	= 2,
		ACT_LAYER	= 3,
		NORM_LAYER	= 4,
		SOFTMAX_LAYER= 5
} LayerType;

/******************************************************************************
 * Layer_t struct : contains information about layers
 *****************************************************************************/

 __global__ void FillOnes(MATRIX_DATA_TYPE *vec, int size)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size)
        return;

    vec[idx] = 1.0f;
}

template <class value_type>
struct Layer_t
{
	LayerType layerType;
	std::string layername;
	int n;			// batch_size

	int inputs, outputs, kernel_dim; // linear dimension (i.e. size is kernel_dim * kernel_dim)
	int  w_size, b_size, d_size;

	int in_height, in_width;
	int out_height, out_width;

	value_type *data_h, 	*data_d;
	value_type *bias_h, 	*bias_d;

	value_type *output_d,	*del_d;

	value_type *oneVec_d;

	// Convolutional Layer
	cudnnConvolutionDescriptor_t convDesc;
	cudnnTensorDescriptor_t convBiasTensorDesc;
	cudnnFilterDescriptor_t convFilterDesc;
	cudnnTensorDescriptor_t convSrcTensorDesc, convDstTensorDesc;
	cudnnConvolutionFwdAlgo_t convFwdAlgo;
	cudnnConvolutionBwdDataAlgo_t convBwdDataAlgo;
	cudnnConvolutionBwdFilterAlgo_t convBwdFilterAlgo;
	size_t convFwdSizeInBytes, convBwdDataSizeInBytes, convBwdFilterSizeInBytes;

	// Pooling Layer
	cudnnPoolingDescriptor_t poolDesc;
	cudnnTensorDescriptor_t poolSrcTensorDesc, poolDstTensorDesc;
	cudnnFilterDescriptor_t poolFilterDesc;
	int size, stride;
	
	// Fully Connected Layer


	// Activation Layer
	cudnnActivationDescriptor_t  activDesc;
	cudnnTensorDescriptor_t actTensorDesc;


	// Normal Layer


	// Softmax Layer


	cudnnDataType_t dataType;
	cudnnTensorFormat_t tensorFormat;

	Layer_t() : data_h(NULL), data_d(NULL), bias_h(NULL), bias_d(NULL), 
				inputs(0), outputs(0), kernel_dim(0)
	{
		switch (sizeof(value_type))
		{
			case 4 : dataType = CUDNN_DATA_FLOAT; break;
			case 8 : dataType = CUDNN_DATA_DOUBLE; break;
			default : FatalError("Unsupported data type");
		}
		tensorFormat = CUDNN_TENSOR_NCHW;
		data_d = bias_d = output_d = del_d = NULL;
		oneVec_d = NULL;
		n = 0;
		convFwdSizeInBytes = convBwdDataSizeInBytes = convBwdFilterSizeInBytes = 0;
	};

	~Layer_t()
	{
		if (data_h != NULL) 	delete [] data_h;
		if (bias_h != NULL) 	delete [] bias_h;

		if (data_d != NULL) 	checkCudaErrors( cudaFree(data_d) );
		if (bias_d != NULL) 	checkCudaErrors( cudaFree(bias_d) );
		if (output_d != NULL) 	checkCudaErrors( cudaFree(output_d) );
		if (del_d != NULL) 		checkCudaErrors( cudaFree(del_d) );

		if (layerType == CONV_LAYER){
			destroyConvLayer();
		} else if (layerType == POOL_LAYER){
			destroyPoolLayer();
		} else if (layerType == ACT_LAYER || layerType == SOFTMAX_LAYER || layerType == NORM_LAYER){
			destroyActLayer();
		} else if (layerType == FC_LAYER){
			destroyLayer();
		}
	}

	void setHandles(int _n)
	{
		if (_n==n)
			return;
		n  = _n;

		if (oneVec_d != NULL) 	checkCudaErrors( cudaFree(oneVec_d) );
		checkCudaErrors( cudaMalloc(&oneVec_d, 	MSIZE(n)) );

		FillOnes<<<1, n>>>(oneVec_d, n);

		if (layerType==CONV_LAYER){
			createConvHandles();
		} else if (layerType==POOL_LAYER){
			createPoolHandles();
		} else if (layerType==ACT_LAYER || layerType==SOFTMAX_LAYER || layerType==NORM_LAYER){
			createActHandles();
		} else {	// FC_LAYER
			createFCHandles();
		}
	}

	void createPoolHandles(){
		int c, h, w;
		c = kernel_dim; h=in_height; w=in_width;
		setTensorDesc(poolSrcTensorDesc, tensorFormat, dataType, n, c, h, w);        

		println("pool in >> n:"<<n<<"\tc:"<<c<<"\th:"<<h<<"\tw:"<<w);
		const int tensorDims = 4;
		int tensorOuputDimA[tensorDims] = {n,c,h,w};
		checkCUDNN( cudnnGetPoolingNdForwardOutputDim(poolDesc,
													poolSrcTensorDesc,
													tensorDims,
													tensorOuputDimA) );
		n = tensorOuputDimA[0]; c = tensorOuputDimA[1];
		h = tensorOuputDimA[2]; w = tensorOuputDimA[3];

		println("pool out >> n:"<<n<<"\tc:"<<c<<"\th:"<<h<<"\tw:"<<w);
		out_height = h;
		out_width  = w;
		
		setTensorDesc(poolDstTensorDesc, tensorFormat, dataType, n, c, h, w);  

		b_size		= kernel_dim * out_width * out_height;
		outputs 	= b_size;
		inputs  	= kernel_dim * in_width * in_height; 
		
		if (output_d != NULL) 	checkCudaErrors( cudaFree(output_d) );
		if (del_d != NULL) 		checkCudaErrors( cudaFree(del_d) );

		checkCudaErrors( cudaMalloc(&output_d, 	MSIZE(n*outputs)) );
		checkCudaErrors( cudaMalloc(&del_d, 	MSIZE(n*inputs)) );
	}

	void createFCHandles(){
		if (output_d != NULL) 	checkCudaErrors( cudaFree(output_d) );
		if (del_d != NULL) 		checkCudaErrors( cudaFree(del_d) );

		checkCudaErrors( cudaMalloc(&output_d, 	MSIZE(n*outputs)) );
		checkCudaErrors( cudaMalloc(&del_d, 	MSIZE(n*inputs)) );
	}

	void createActHandles(){
		int c, h, w;
		h = w = 1; c = inputs;
		setTensorDesc(actTensorDesc, tensorFormat, dataType, n, c, h, w);

		if (output_d != NULL) 	checkCudaErrors( cudaFree(output_d) );
		if (del_d != NULL) 		checkCudaErrors( cudaFree(del_d) );
		
		checkCudaErrors( cudaMalloc(&output_d, 	MSIZE(n*outputs)) );
		checkCudaErrors( cudaMalloc(&del_d, 	MSIZE(n*inputs)) );
	}

	void createConvHandles()
	{
		int c = inputs;
		int h = in_height;
		int w = in_width;

		println("conv in >> n:"<<n<<"\tc:"<<c<<"\th:"<<h<<"\tw:"<<w);
        checkCUDNN(cudnnSetTensor4dDescriptor(convSrcTensorDesc,
                                              tensorFormat,
                                              dataType,
                                              n, c,
                                              h, w));

        checkCUDNN(cudnnSetTensor4dDescriptor(convBiasTensorDesc,
                                              tensorFormat,
                                              dataType,
                                              1, outputs,
                                              1, 1));

        checkCUDNN(cudnnSetFilter4dDescriptor(convFilterDesc,
                                              dataType,
                                              tensorFormat,
                                              outputs, inputs, 
											  kernel_dim, kernel_dim));
 
        checkCUDNN(cudnnSetConvolution2dDescriptor(convDesc,
                                                   0, 0,	//	padding
                                                   stride, stride,	//	stride
                                                   1, 1,	// 	upscaling
                                                   CUDNN_CROSS_CORRELATION));
        // Find dimension of convolution output
        checkCUDNN(cudnnGetConvolution2dForwardOutputDim(convDesc,
                                                         convSrcTensorDesc,
                                                         convFilterDesc,
                                                         &n, &c, &h, &w));

        out_width 	= w;			
		out_height 	= h;

		println("conv out >> n:"<<n<<"\tc:"<<c<<"\th:"<<h<<"\tw:"<<w);
        checkCUDNN(cudnnSetTensor4dDescriptor(convDstTensorDesc,
                                              tensorFormat,
                                              dataType,
                                              n, c,
                                              h, w));
        cudnnHandle_t cudnnHandle;
		checkCUDNN( cudnnCreate(&cudnnHandle) );

		convFwdAlgo = CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_GEMM;
        // checkCUDNN(cudnnGetConvolutionForwardAlgorithm(cudnnHandle,
        //                                                convSrcTensorDesc,
        //                                                convFilterDesc,
        //                                                convDesc,
        //                                                convDstTensorDesc,
        //                                                CUDNN_CONVOLUTION_FWD_PREFER_FASTEST,
        //                                                0,
        //                                                &convFwdAlgo));
        
        checkCUDNN(cudnnGetConvolutionForwardWorkspaceSize(cudnnHandle,
                                                           convSrcTensorDesc,
                                                           convFilterDesc,
                                                           convDesc,
                                                           convDstTensorDesc,
                                                           convFwdAlgo,
                                                           &convFwdSizeInBytes));
        
        convBwdDataAlgo = CUDNN_CONVOLUTION_BWD_DATA_ALGO_0;
  		// checkCUDNN( cudnnGetConvolutionBackwardDataAlgorithm(cudnnHandle,
  		// 													convFilterDesc,
  		// 													convDstTensorDesc,
  		// 													convDesc,
  		// 													convSrcTensorDesc,
  		// 													CUDNN_CONVOLUTION_BWD_DATA_PREFER_FASTEST,
  		// 													0,
  		// 													&convBwdDataAlgo));

  		checkCUDNN( cudnnGetConvolutionBackwardDataWorkspaceSize(cudnnHandle,
														convFilterDesc,
														convDstTensorDesc,
														convDesc,
														convSrcTensorDesc,
														convBwdDataAlgo,
														&convBwdDataSizeInBytes
														));

  		convBwdFilterAlgo = CUDNN_CONVOLUTION_BWD_FILTER_ALGO_1;
  		// checkCUDNN( cudnnGetConvolutionBackwardFilterAlgorithm(cudnnHandle,
  		// 														convSrcTensorDesc,
  		// 														convDstTensorDesc,
  		// 														convDesc,
  		// 														convFilterDesc,
  		// 														CUDNN_CONVOLUTION_BWD_FILTER_PREFER_FASTEST,
  		// 														0,
  		// 														&convBwdFilterAlgo));
  		checkCUDNN( cudnnGetConvolutionBackwardFilterWorkspaceSize(cudnnHandle,
												convSrcTensorDesc,
												convDstTensorDesc,
												convDesc,
												convFilterDesc,
												convBwdFilterAlgo,
												&convBwdFilterSizeInBytes));

  		//println("handles: "<<(int)convFwdAlgo<<" "<<(int)convBwdDataAlgo<<" "<<(int)convBwdFilterAlgo);

        checkCUDNN( cudnnDestroy(cudnnHandle) );

        if (data_d != NULL) 	checkCudaErrors( cudaFree(data_d) );
		if (bias_d != NULL) 	checkCudaErrors( cudaFree(bias_d) );
		if (output_d != NULL) 	checkCudaErrors( cudaFree(output_d) );
		if (del_d != NULL) 		checkCudaErrors( cudaFree(del_d) );

        checkCudaErrors( cudaMalloc(&data_d, 	MSIZE(w_size)) );
		checkCudaErrors( cudaMalloc(&bias_d, 	MSIZE(b_size)) );
		checkCudaErrors( cudaMalloc(&output_d, 	MSIZE(n*outputs*out_height*out_width)) );
		checkCudaErrors( cudaMalloc(&del_d, 	MSIZE(n*d_size)) );
	}

	void initConvLayer(std::string _layername, int _inputs, int _outputs, int _kernel_dim, int _stride, int _in_height, int _in_width, int _d_size=0, int _batch_size=1)
	{
		layerType 	= CONV_LAYER;
		layername 	= _layername;
		inputs 		= _inputs;
		outputs 	= _outputs;
		kernel_dim 	= _kernel_dim;
		stride 		= _stride;
		in_width 	= _in_width;
		in_height 	= _in_height;
		w_size 		= inputs*outputs*kernel_dim*kernel_dim;
		b_size 		= outputs;
		d_size 		= _d_size;

		data_h 	= new value_type[w_size];
		bias_h 	= new value_type[b_size];

		// Random Initialization
		// TODO : Fix this random initialization
		for (int i=0; i<w_size; i++)
			data_h[i] = (((value_type)rand())/(rand()+1))/100000;
		for (int i=0; i<b_size; i++)
			bias_h[i] = (((value_type)rand())/(rand()+1))/100000;
		
		
		checkCUDNN(cudnnCreateTensorDescriptor(&convSrcTensorDesc));
		checkCUDNN(cudnnCreateTensorDescriptor(&convDstTensorDesc));
		checkCUDNN(cudnnCreateFilterDescriptor(&convFilterDesc));
		checkCUDNN(cudnnCreateConvolutionDescriptor(&convDesc));
		checkCUDNN(cudnnCreateTensorDescriptor(&convBiasTensorDesc));

		setHandles(_batch_size);

		copyDataToDevice();
	}

	void initPoolLayer(std::string _layername, int _size, int _stride, Layer_t<value_type>& conv, int _batch_size=1)
	{
		layerType 	= POOL_LAYER;
		layername 	= _layername;
		size 		= _size;
		stride 		= _stride;
		w_size		= 0;
		kernel_dim  = conv.outputs;
		in_height 	= conv.out_height;
		in_width 	= conv.out_width;		

		checkCUDNN(cudnnCreateTensorDescriptor(&poolSrcTensorDesc));
		checkCUDNN(cudnnCreateTensorDescriptor(&poolDstTensorDesc));
		checkCUDNN(cudnnCreatePoolingDescriptor(&poolDesc));
		checkCUDNN(cudnnSetPooling2dDescriptor(poolDesc,
											   CUDNN_POOLING_MAX,
											   CUDNN_PROPAGATE_NAN,
											   size, size,
											   0, 0,
											   stride, stride));

		setHandles(_batch_size);
	}

	void initFCLayer(std::string _layername, int _inputs, int _outputs, int _batch_size=1)
	{
		layerType 	= FC_LAYER;
		layername 	= _layername;
		inputs 		= _inputs;
		outputs 	= _outputs;
		kernel_dim 	= 1;
		w_size 		= inputs*outputs*kernel_dim*kernel_dim;
		b_size 		= outputs;

		data_h 	= new value_type[w_size];
		bias_h 	= new value_type[b_size];

		// Random Initialization
		// TODO : Fix this random initialization
		for (int i=0; i<w_size; i++)
			data_h[i] = (((value_type)rand())/(rand()+1))/100000;
		for (int i=0; i<b_size; i++)
			bias_h[i] = (((value_type)rand())/(rand()+1))/100000;			
		
		
		checkCudaErrors( cudaMalloc(&data_d, 	MSIZE(w_size)) );
		checkCudaErrors( cudaMalloc(&bias_d, 	MSIZE(b_size)) );
		
		setHandles(_batch_size);

		copyDataToDevice();
	}

	void initActLayer(std::string _layername, int _outputs, int _batch_size=1){
		initLayer(_layername, ACT_LAYER, _outputs, _batch_size);
	}

	void initSoftmaxLayer(std::string _layername, int _outputs, int _batch_size=1){
		initLayer(_layername, SOFTMAX_LAYER, _outputs, _batch_size);
	}

	

	void destroyConvLayer(){
		checkCUDNN(cudnnDestroyTensorDescriptor(convSrcTensorDesc));
		checkCUDNN(cudnnDestroyTensorDescriptor(convDstTensorDesc));
		checkCUDNN(cudnnDestroyFilterDescriptor(convFilterDesc));
		checkCUDNN(cudnnDestroyConvolutionDescriptor(convDesc));
		checkCUDNN(cudnnDestroyTensorDescriptor(convBiasTensorDesc));
	}

	void destroyPoolLayer(){
		checkCUDNN(cudnnDestroyTensorDescriptor(poolSrcTensorDesc));
		checkCUDNN(cudnnDestroyTensorDescriptor(poolDstTensorDesc));
		checkCUDNN(cudnnDestroyPoolingDescriptor(poolDesc));
	}

	void destroyActLayer(){
		checkCUDNN( cudnnDestroyActivationDescriptor(activDesc) );
		checkCUDNN( cudnnDestroyTensorDescriptor(actTensorDesc) );
	}

	void destroyLayer(){

	}

	void copyDataToDevice(){
		if (data_h!=NULL) 	checkCudaErrors( cudaMemcpy(data_d, 	data_h, 	MSIZE(w_size), 	cudaMemcpyHostToDevice) );
		if (bias_h!=NULL) 	checkCudaErrors( cudaMemcpy(bias_d, 	bias_h, 	MSIZE(b_size), 	cudaMemcpyHostToDevice) );
	}
	
	void copyDataToHost(){
		if (data_h!=NULL) 	checkCudaErrors( cudaMemcpy(data_h, 	data_d, 	MSIZE(w_size), 	cudaMemcpyDeviceToHost) );
		if (bias_h!=NULL) 	checkCudaErrors( cudaMemcpy(bias_h, 	bias_d, 	MSIZE(b_size), 	cudaMemcpyDeviceToHost) );
	}

	bool load(){
		std::string dtype = (sizeof(value_type)==4?"_float_":"_double_");
		return loadWeights(layername+dtype+"weights.bin", w_size, data_h) && loadWeights(layername+dtype+"bias.bin", b_size, bias_h);
	}

	bool save(){
		std::string dtype = (sizeof(value_type)==4?"_float_":"_double_");
		return saveWeights(layername+dtype+"weights.bin", w_size, data_h) && saveWeights(layername+dtype+"bias.bin", b_size, bias_h);
	}

	bool loadWeights(std::string filename, size_t size, value_type* matrix){
		filename = weights_folder+filename;
		std::ifstream myfile(filename.c_str(), std::ios::in | std::ios::binary);
		if (myfile.is_open()){
			myfile.read((char*)matrix, MSIZE(size));
			return true;
		}else{
			println("Error reading file "<<filename);
			return false;
		}
	}

	bool saveWeights(std::string filename, size_t size, value_type* matrix){
		filename = weights_folder+filename;
		std::ofstream myfile(filename.c_str(), std::ios::out | std::ios::binary);
		if (myfile.is_open()){
			myfile.write((char*)matrix, MSIZE(size));
			return true;
		}else{
			println("Error saving file "<<filename);
			return false;
		}
	}
private:
	void initLayer(std::string _layername, LayerType _layerType, int _outputs, int _batch_size=1){
		layerType 	= _layerType;
		layername 	= _layername;
		inputs 		= _outputs;
		outputs 	= _outputs;
		kernel_dim 	= 1;
		w_size 		= 0;
		b_size 		= 0;
		
		checkCUDNN( cudnnCreateActivationDescriptor(&activDesc) );
		checkCUDNN( cudnnCreateTensorDescriptor(&actTensorDesc) );
		checkCUDNN( cudnnSetActivationDescriptor(activDesc,
												CUDNN_ACTIVATION_RELU, //CUDNN_ACTIVATION_SIGMOID,
												CUDNN_PROPAGATE_NAN,
												0.0) );

		setHandles(_batch_size);
	}

	void readAllocInit(const char* fname, int size, value_type** data_h, value_type** data_d)
	{
		readAllocMemcpy<value_type>(fname, size, data_h, data_d);
	}
};


/******************************************************************************
 * network_t class : contains all learning functions
 *****************************************************************************/

__global__ void getDiffDataD(MATRIX_DATA_TYPE* targets, MATRIX_DATA_TYPE* diffData, int label_count, int _batch_size){
 	int idx = threadIdx.x;
 	if (idx>=_batch_size)
 		return;
 	const int label_value = static_cast<int>(targets[idx]);
 	diffData[ idx * label_count + label_value] -= 1;
}

template <class value_type>
class network_t
{
	cudnnHandle_t cudnnHandle;
	cublasHandle_t cublasHandle;
	value_type vOne, vZero;

	void createHandles()
	{
		checkCUDNN( cudnnCreate(&cudnnHandle) );
		checkCublasErrors( cublasCreate(&cublasHandle) );
	}

	void destroyHandles()
	{
		checkCUDNN( cudnnDestroy(cudnnHandle) );
		checkCublasErrors( cublasDestroy(cublasHandle) );
	}
  public:
	network_t()
	{
		vOne  = value_type(1);
		vZero = value_type(0);
		createHandles();    
	};

	~network_t()
	{
		destroyHandles();
	}
	
	void resize(int size, value_type **data)
	{
		if (*data != NULL)
		{
			checkCudaErrors( cudaFree(*data) );
		}
		checkCudaErrors( cudaMalloc(data, MSIZE(size)) );
	}
	
	void addBias(const cudnnTensorDescriptor_t& convDstTensorDesc, Layer_t<value_type>& layer, int c, value_type *data)
	{
		checkCUDNN( cudnnAddTensor( cudnnHandle, 
									&vOne, 
									layer.convBiasTensorDesc,
									layer.bias_d,
									&vOne,
									convDstTensorDesc,
									data) );
	}

	void fullyConnectedForward(Layer_t<value_type>& layer,
						  int& n,
						  value_type* srcData)
	{
		layer.setHandles(n);

		
		// int dim_x = layer.inputs;
		// int dim_y = layer.outputs;
		
		// checkCudaErrors( cudaMemcpy(layer.output_d, layer.bias_d, MSIZE(dim_y), cudaMemcpyDeviceToDevice) );
		
		// checkCublasErrors( CUBLAS_GEMV(cublasHandle, CUBLAS_OP_T,
  		//                          dim_x, dim_y,
  		//                          &vOne,
  		//                          layer.data_d, dim_x,
  		//                          srcData, 1,
  		//                          &vOne,
  		//                          layer.output_d, 1) );    

		// Forward propagate neurons using weights (fc1 = pfc1'*pool2)
        checkCudaErrors(CUBLAS_GEMM(cublasHandle, CUBLAS_OP_T, CUBLAS_OP_N,
                                    layer.outputs, n, layer.inputs,
                                    &vOne,
                                    layer.data_d, layer.inputs,
                                    srcData, layer.inputs,
                                    &vZero,
                                    layer.output_d, layer.outputs));
        // printDeviceVector("One Vector:\n", n, layer.oneVec_d);
        // Add bias using GEMM's "beta" (fc1 += pfc1bias*1_vec')
        checkCudaErrors(CUBLAS_GEMM(cublasHandle, CUBLAS_OP_N, CUBLAS_OP_N,
                                    layer.outputs, n, 1,
                                    &vOne,
                                    layer.bias_d, layer.outputs,
                                    layer.oneVec_d, 1,
                                    &vOne,
                                    layer.output_d, layer.outputs));

	}

	void convoluteForward(Layer_t<value_type>& layer,
						  int& n, 
						  value_type* srcData)
	{
		layer.setHandles(n);

		if (DEBUG) printDeviceVector("Conv Weights:\n", layer.w_size, layer.data_d);
		if (DEBUG) printDeviceVector("Conv Bias:\n", layer.b_size, layer.bias_d);
		void* workSpace=NULL;
		if (layer.convFwdSizeInBytes!=0)
		{
		  checkCudaErrors( cudaMalloc(&workSpace,layer.convFwdSizeInBytes) );
		}
		checkCUDNN( cudnnConvolutionForward(cudnnHandle,
											  &vOne,
											  layer.convSrcTensorDesc,
											  srcData,
											  layer.convFilterDesc,
											  layer.data_d,
											  layer.convDesc,
											  layer.convFwdAlgo,
											  workSpace,
											  layer.convFwdSizeInBytes,
											  &vZero,
											  layer.convDstTensorDesc,
											  layer.output_d) );
		addBias(layer.convDstTensorDesc, layer, layer.outputs, layer.output_d);
		if (DEBUG) printDeviceVector("Conv Output:\n", layer.outputs*layer.out_height*layer.out_width, layer.output_d);
		if (layer.convFwdSizeInBytes!=0)
		{
		  checkCudaErrors( cudaFree(workSpace) );
		}
	}

	void convoluteBackward(Layer_t<value_type>& layer,
							int& n,
							value_type* diffData)
	{
		void* workSpace=NULL;
		if (layer.convBwdDataSizeInBytes!=0)
		{
		  checkCudaErrors( cudaMalloc(&workSpace,layer.convBwdDataSizeInBytes) );
		}
		checkCUDNN(cudnnConvolutionBackwardData(cudnnHandle, 
												&vOne, 
												layer.convFilterDesc, layer.data_d, 
												layer.convDstTensorDesc, diffData, 
												layer.convDesc, layer.convBwdDataAlgo,
												workSpace, layer.convBwdDataSizeInBytes,
												&vZero, 
												layer.convSrcTensorDesc, layer.del_d));
		if (layer.convBwdDataSizeInBytes!=0)
		{
		  checkCudaErrors( cudaFree(workSpace) );
		}
	}

	void poolForward(Layer_t<value_type>& layer,
					  int& n, 
					  value_type* srcData)
	{
		layer.setHandles(n);

		if (DEBUG) printDeviceVector("Pooling Input:\n", layer.inputs, layer.output_d);
		checkCUDNN( cudnnPoolingForward(cudnnHandle,
										  layer.poolDesc,
										  &vOne,
										  layer.poolSrcTensorDesc,
										  srcData,
										  &vZero,
										  layer.poolDstTensorDesc,
										  layer.output_d) );
		if (DEBUG) printDeviceVector("Pooling Output:\n", layer.outputs, layer.output_d);
	}

	void poolBackward(Layer_t<value_type>& layer,
						int& n,
						value_type* diffData, value_type* srcData)
	{

		if (DEBUG) printDeviceVector("Pooling back Input: ", layer.outputs, srcData);
		checkCUDNN(cudnnPoolingBackward(cudnnHandle, 
											layer.poolDesc, 
											&vOne, 
											layer.poolDstTensorDesc, layer.output_d, 
											layer.poolDstTensorDesc, diffData,
											layer.poolSrcTensorDesc, srcData, 
											&vZero, 
											layer.poolSrcTensorDesc, layer.del_d));
		if (DEBUG) printDeviceVector("Pooling back Output: ", layer.inputs, layer.del_d);

	}

	void softmaxForward(Layer_t<value_type>& layer, 
						int &n, value_type* srcData)
	{
		layer.setHandles(n);
		checkCUDNN( cudnnSoftmaxForward(cudnnHandle,
										  CUDNN_SOFTMAX_ACCURATE ,
										  CUDNN_SOFTMAX_MODE_CHANNEL,
										  &vOne,
										  layer.actTensorDesc,
										  srcData,
										  &vZero,
										  layer.actTensorDesc,
										  layer.output_d) );
	}

	void getDiffData(Layer_t<value_type>& layer, int target, value_type** diffData){
		resize(layer.outputs, diffData);
		value_type outputh[layer.outputs];
		checkCudaErrors( cudaMemcpy(outputh, layer.output_d, MSIZE(layer.outputs), cudaMemcpyDeviceToHost) );
		for (int i=0; i<layer.outputs; i++){
			if (i==target)
				outputh[i] -= 1 ;
		}
		checkCudaErrors( cudaMemcpy(*diffData, outputh, MSIZE(layer.outputs), cudaMemcpyHostToDevice) );
	}

	void softmaxBackward(Layer_t<value_type>& layer, 
						int &n, 
						value_type* diffData, value_type* srcData)
	{
		checkCUDNN( cudnnSoftmaxBackward(cudnnHandle,
										  CUDNN_SOFTMAX_ACCURATE ,
										  CUDNN_SOFTMAX_MODE_CHANNEL,
										  &vOne,
										  layer.actTensorDesc,
										  layer.output_d,
										  layer.actTensorDesc,
										  diffData,
										  &vZero,
										  layer.actTensorDesc,
										  layer.del_d) );
	}

	void activationForward(Layer_t<value_type>& layer, 
							int &n, value_type* srcData)
	{
		layer.setHandles(n);
		checkCUDNN( cudnnActivationForward(cudnnHandle,
											layer.activDesc,
											&vOne,
											layer.actTensorDesc,
											srcData,
											&vZero,
											layer.actTensorDesc,
											layer.output_d) );    
	}

	void fullyConnectedBackward(Layer_t<value_type>& layer,
								int &n, value_type* srcData)
	{
		// checkCudaErrors( CUBLAS_GEMV(cublasHandle, CUBLAS_OP_N,
		// 							  layer.inputs, layer.outputs,
		// 							  &vOne,
		// 							  layer.data_d, layer.inputs,
		// 							  srcData, 1,
		// 							  &vZero,
		// 							  layer.del_d, 1) );

		checkCudaErrors( CUBLAS_GEMM(cublasHandle, CUBLAS_OP_N, CUBLAS_OP_N,
									  layer.inputs, n, layer.outputs,
									  &vOne,
									  layer.data_d, layer.inputs,
									  srcData, layer.outputs,
									  &vZero,
									  layer.del_d, layer.inputs) );
	}

	void activationBackward(Layer_t<value_type>& layer,
							int &n, 
							value_type *srcDiffData, value_type* srcData)
	{
		checkCUDNN( cudnnActivationBackward(cudnnHandle,
											layer.activDesc,
											&vOne,
											layer.actTensorDesc,
											layer.output_d,
											layer.actTensorDesc,
											srcDiffData,
											layer.actTensorDesc,
											srcData,
											&vZero,
											layer.actTensorDesc,
											layer.del_d
											) );    
	}

	void fullyConnectedUpdateWeights(Layer_t<value_type>& layer, value_type* diffData, value_type* srcData, int n){
		value_type* dstData = NULL;
		resize(layer.inputs*layer.outputs, &dstData);
		value_type lr = value_type(-learning_rate); // learning rate

		//if (DEBUG) printDeviceVector("last_input: \n", layer.inputs, last_input);
		//if (DEBUG) printDeviceVector("del_W: \n", layer.outputs, layer.del_d);
		
		checkCudaErrors( CUBLAS_GEMM(cublasHandle, 
									  CUBLAS_OP_N, CUBLAS_OP_T,
									  layer.inputs, layer.outputs, n,
									  &vOne,
									  srcData, layer.inputs,
									  diffData, layer.outputs,
									  &vZero,
									  dstData, layer.inputs) );

		// if (DEBUG) printDeviceVector("\tdelta_W (del_W*hidden_input): \n", layer.inputs*layer.outputs, dstData);

		
		const value_type* B = layer.data_d;
		// C = α op ( A ) + β * C
		// C = 0.1 * delta_W2 + C
		// if (DEBUG) printDeviceVector("\tW = W + 0.1*delta_W: old\n", layer.inputs*layer.outputs, layer.data_d);
		
		checkCudaErrors( CUBLAS_GEAM(cublasHandle,
										CUBLAS_OP_N, CUBLAS_OP_N,
										layer.inputs, layer.outputs,
										&lr,
										dstData, layer.inputs,
										&vOne,
										B, layer.inputs,
										layer.data_d, layer.inputs) );
		// if (DEBUG) printDeviceVector("\tW: \n", layer.inputs*layer.outputs, layer.data_d);

		// printDeviceVector("\n yo \n", layer.outputs, diffData, n);
		// printDeviceVector("\n ones \n", n, layer.oneVec_d);
		resize(layer.outputs, &dstData);

		checkCudaErrors( CUBLAS_GEMV(cublasHandle, 
										CUBLAS_OP_N, 
										layer.outputs, n,
                                    	&vOne, 
                                    	diffData, layer.outputs, 
                                    	layer.oneVec_d, 1, 
                                    	&vZero, 
                                    	dstData, 1));
		// printDeviceVector("\n sum \n", layer.outputs, dstData);

		// place bias into dstData
		const value_type* B2 = layer.bias_d;
		// if (DEBUG) printDeviceVector("\tdel_W:\n", layer.outputs, layer.del_d);
		// if (DEBUG) printDeviceVector("\tB = B + 0.1*del_W: old\n", layer.outputs, layer.bias_d);
		checkCudaErrors( CUBLAS_GEAM(cublasHandle,
										CUBLAS_OP_N, CUBLAS_OP_N,
										1, layer.outputs,
										&lr,
										dstData, 1,
										&vOne,
										B2, 1,
										layer.bias_d, 1) );
		// if (DEBUG) printDeviceVector("\tB:\n", layer.outputs, layer.bias_d);

		checkCudaErrors( cudaFree(dstData));
	}

	void convolutionalUpdateWeights(Layer_t<value_type>& layer, value_type* diffData, value_type* srcData)
	{

		if (DEBUG) println("Convolutional Update Weights:");

		value_type *gconvB = NULL, *gconvW = NULL;
		resize(layer.outputs, &gconvB);
		resize(layer.w_size, &gconvW);
		
		checkCUDNN(cudnnConvolutionBackwardBias(cudnnHandle, 
												&vOne, 
												layer.convDstTensorDesc, diffData, 
												&vZero, 
												layer.convBiasTensorDesc, gconvB));

		if (DEBUG) printDeviceVector(" gconvB: ", layer.outputs, gconvB);

		void* workSpace=NULL;
		
		if (layer.convBwdFilterSizeInBytes!=0)
		{
		  checkCudaErrors( cudaMalloc(&workSpace,layer.convBwdFilterSizeInBytes) );
		}
		checkCUDNN(cudnnConvolutionBackwardFilter(cudnnHandle, 
												&vOne, 
												layer.convSrcTensorDesc, srcData, 
												layer.convDstTensorDesc, diffData, 
												layer.convDesc, layer.convBwdFilterAlgo,
												workSpace, layer.convBwdFilterSizeInBytes,
												&vZero, 
												layer.convFilterDesc, gconvW));
		if (layer.convBwdFilterSizeInBytes!=0)
		{
		  checkCudaErrors( cudaFree(workSpace) );
		}

		if (DEBUG) printDeviceVector(" gconvW: ", layer.w_size, gconvW);

		value_type lr = value_type(-learning_rate); // learning rate
		checkCudaErrors(cublasDaxpy(cublasHandle, 
									layer.outputs*layer.inputs*layer.kernel_dim*layer.kernel_dim,
									&lr, 
									gconvW, 1, 
									layer.data_d, 1));
		checkCudaErrors(cublasDaxpy(cublasHandle, 
									layer.outputs,
									&lr, 
									gconvB, 1, 
									layer.bias_d, 1));

		if (DEBUG) printDeviceVector(" Updated Weights: ", layer.w_size, layer.data_d);
		if (DEBUG) printDeviceVector(" Updated Bias: ", layer.b_size, layer.bias_d);
		
		checkCudaErrors( cudaFree(gconvB) );
		checkCudaErrors( cudaFree(gconvW) );
		if (DEBUG) getchar();
	}

	
	#ifdef LENET
	void predict_example(value_type* image_data_d, 
						LAYER_NAMES_WITH_TYPE,
						value_type *predictions,
						int _batch_size=1)
	{
		int n = _batch_size;
		// if (DEBUG) println("Performing forward propagation ...");

		convoluteForward(conv1, n, image_data_d);
		poolForward(pool1, 		n, conv1.output_d);

		convoluteForward(conv2, n, pool1.output_d);
		poolForward(pool2, 		n, conv2.output_d);

		fullyConnectedForward(fc1, 	n, pool2.output_d);
		activationForward(fc1act, 	n, fc1.output_d);

		fullyConnectedForward(fc2, 	n, fc1act.output_d);
		activationForward(fc2act, 	n, fc2.output_d);
		// softmaxForward(fc2act, 	n, fc2.output_d);

		const int max_digits = fc2act.outputs;
		
		value_type result[n*max_digits];
		checkCudaErrors( cudaMemcpy(result, fc2act.output_d, MSIZE(n*max_digits), cudaMemcpyDeviceToHost) );
		for (int batch=0; batch<n; batch++)
		{		
			predictions[batch] = 0;
			for (int i = 1; i < max_digits; i++)
			{
				if ((result[(int)predictions[batch]]) < (result[i])) predictions[batch] = i;
			}
		}	
	}

	void learn_example(value_type* image_data_d, 
						LAYER_NAMES_WITH_TYPE,
						value_type* targets,
						int _batch_size=1)
	{
		int n,c;
		
		n = _batch_size; c = fc2act.outputs;
		
		value_type predictions[n];

		predict_example(image_data_d, conv1, pool1, conv2, pool2, fc1, fc1act, fc2, fc2act, predictions, _batch_size);

		//if (DEBUG) println("Performing backward propagation ...");

		value_type *diffData = NULL;
		resize(n*c, &diffData);
		checkCudaErrors( cudaMemcpy(diffData, fc2act.output_d, MSIZE(n*c), cudaMemcpyDeviceToDevice) );
		
		getDiffDataD<<<1, n>>>(targets, diffData, c, n);
		cudaDeviceSynchronize();

		value_type scalVal = 1.0f / static_cast<value_type>(n);
		checkCudaErrors(CUBLAS_SCAL(cublasHandle, n * c, &scalVal, diffData, 1));

		activationBackward(fc2act,	n, diffData, fc2.output_d);
		// softmaxBackward(fc2act,		n, diffData, fc2.output_d);
		fullyConnectedBackward(fc2, n, fc2act.del_d);

		activationBackward(fc1act, 	n, fc2.del_d, fc1.output_d);
		fullyConnectedBackward(fc1, n, fc1act.del_d);		


		poolBackward(pool2,			n, fc1.del_d, conv2.output_d);
		convoluteBackward(conv2,	n, pool2.del_d);

		poolBackward(pool1,			n, conv2.del_d, conv1.output_d);


		// Update Weights
		fullyConnectedUpdateWeights(fc2, fc2act.del_d, fc1act.output_d, n);
		fullyConnectedUpdateWeights(fc1, fc1act.del_d,  pool1.output_d, n);

		convolutionalUpdateWeights(conv2, pool2.del_d, pool1.output_d);
		convolutionalUpdateWeights(conv1, pool1.del_d, image_data_d);

		checkCudaErrors( cudaFree(diffData) );
	}
	#endif
	

	#ifdef FFNET
	void predict_example(value_type* image_data_d,
						LAYER_NAMES_WITH_TYPE,
						value_type *predictions,
						int _batch_size=1)
	{
		int n = _batch_size;
		// if (DEBUG) println("Performing forward propagation ...");

		fullyConnectedForward(fc1, 	n, image_data_d);
		activationForward(fc1act, 	n, fc1.output_d);

		fullyConnectedForward(fc2, 	n, fc1act.output_d);
		// activationForward(fc2act, 	n, fc2.output_d);
		softmaxForward(fc2act, 	n, fc2.output_d);

		const int max_digits = fc2act.outputs;
		
		value_type result[n*max_digits];
		checkCudaErrors( cudaMemcpy(result, fc2act.output_d, MSIZE(n*max_digits), cudaMemcpyDeviceToHost) );
		for (int batch=0; batch<n; batch++)
		{		
			predictions[batch] = 0;
			for (int i = 1; i < max_digits; i++)
			{
				if ((result[(int)predictions[batch]]) < (result[i])) predictions[batch] = i;
			}
		}	
	}
	
	void learn_example(value_type* image_data_d, 
						LAYER_NAMES_WITH_TYPE,
						value_type* targets,
						int _batch_size=1)
	{
		int n = _batch_size, c = fc2act.outputs;

		value_type predictions[n];

		predict_example(image_data_d, fc1, fc1act, fc2, fc2act, predictions, _batch_size);

		//if (DEBUG) println("Performing backward propagation ...");
		value_type *diffData = NULL;
		resize(n*c, &diffData);
		checkCudaErrors( cudaMemcpy(diffData, fc2act.output_d, MSIZE(n*c), cudaMemcpyDeviceToDevice) );

		getDiffDataD<<<1, n>>>(targets, diffData, c, n);
		cudaDeviceSynchronize();

		value_type scalVal = 1.0f / static_cast<value_type>(n);
		checkCudaErrors(CUBLAS_SCAL(cublasHandle, n * c, &scalVal, diffData, 1));

		// activationBackward(fc2act,	n, diffData, fc2.output_d);
		softmaxBackward(fc2act,		n, diffData, fc2.output_d);
		fullyConnectedBackward(fc2, n, fc2act.del_d);

		activationBackward(fc1act, 	n, fc2.del_d, fc1.output_d);
		// fullyConnectedBackward(fc1, n, fc1act.del_d);		


		// Update Weights
		fullyConnectedUpdateWeights(fc2, fc2act.del_d, fc1act.output_d, n);
		fullyConnectedUpdateWeights(fc1, fc1act.del_d,  image_data_d,   n);

		checkCudaErrors( cudaFree(diffData) );
	}
	#endif
	

	static void load_mnist_data(value_type **training_data, value_type **testing_data,
		 value_type **training_target, value_type **testing_target,
		 int &total_train_size, int &total_test_size)
	{
		std::string name;
		total_train_size = 0;
		total_test_size = 0;
		std::string fname;
		std::stringstream error_s;

		// Calculate total training and testing size
		for (int t=0; t<2; t++){
			name = t==0?"train":"test";
			for (int d=0; d<10; d++){
				std::stringstream sstm;
				sstm<<"data/"<<name<<d<<".bin";
				fname = sstm.str();
				std::ifstream dataFile (fname.c_str(), std::ios::in | std::ios::binary);
				if (!dataFile)
				{
					error_s << "Error opening file " << fname; 
					FatalError(error_s.str());
				}

				dataFile.seekg(0, std::ios::end);
				size_t file_size = static_cast<std::string::size_type>(dataFile.tellg());
				dataFile.seekg(0, std::ios::beg);		
				dataFile.close();
				// println("Calculating file "<<fname<<"\t"<<file_size);
				if (t==0)
					total_train_size += file_size;
				else
					total_test_size += file_size;
			 }
		}

		*training_data = new value_type[total_train_size];
		*testing_data = new value_type[total_test_size];
		*training_target = new value_type[total_train_size/N];
		*testing_target = new value_type[total_test_size/N];
		total_train_size = 0;
		total_test_size = 0;
		for (int t=0; t<2; t++){
			name = t==0?"train":"test";
			for (int d=0; d<10; d++){
				std::stringstream sstm;
				sstm<<"data/"<<name<<d<<".bin";
				fname = sstm.str();
				std::ifstream dataFile (fname.c_str(), std::ios::in | std::ios::binary);
				if (!dataFile)
				{
					error_s << "Error opening file " << fname; 
					FatalError(error_s.str());
				}

				dataFile.seekg(0, std::ios::end);
				size_t file_size = static_cast<std::string::size_type>(dataFile.tellg());
				dataFile.seekg(0, std::ios::beg);		
				
				char *data = new char[file_size];
				if (!dataFile.read (data, file_size)) 
				{
					error_s << "Error reading file " << fname; 
					FatalError(error_s.str());
				}
				dataFile.close();

				value_type v;
				int m = file_size/N;
				// println("Reading file "<<fname<<" "<<file_size<<" "<<m);
				for (int i=0; i<file_size; i++){
					v = static_cast<value_type>((uint8_t)data[(i/N)+m*(i%N) ]);
					if (t==0){
						(*training_data)[total_train_size+i] = v;
						if (i<m)
							(*training_target)[total_train_size/N+i] = d;
					}
					else {  
						(*testing_data)[total_test_size+i] = v;
						if (i<m)
							(*testing_target)[total_test_size/N+i] = d;
					}
				}
				if (t==0)
					total_train_size += file_size;
				else
					total_test_size += file_size;
				delete [] data; 
			 }
		}
	}
};

/******************************************************************************
 * HELPER FUNCTIONS for main()
 *****************************************************************************/

void displayUsage()
{
	println( "mnistCUDNN {<options>}");
	println( "help                   : display this help");
	println( "device=<int>           : set the device to run the sample");
}

template <typename value_type> 
void readImageToDevice(const char* fname, value_type **image_data_d){
	value_type imgData_h[N];
	readImage(fname, imgData_h);
	checkCudaErrors( cudaMalloc(&image_data_d, MSIZE(N)) );
	checkCudaErrors( cudaMemcpy(image_data_d, imgData_h, MSIZE(N), cudaMemcpyHostToDevice) );
}

void run_mnist()
{
	typedef MATRIX_DATA_TYPE value_type;

	// Define and initialize network
	const double base_learning_rate = 0.01;
	const double base_power = 0.75;
	const int batch_size = 16;
	const double base_gamma = BASE_GAMMA;

	network_t<value_type> mnist;
	NETWORK_ARCH

	// Contains Training and Testing Examples
	value_type *train_data, *testing_data;
	value_type *train_target, *testing_target;

	// Read training data in tempraroy variables
	value_type *temp_training_data;
	value_type *temp_training_target;

	int total_train_data, total_test_data;
	mnist.load_mnist_data(&temp_training_data, &testing_data, &temp_training_target, &testing_target, total_train_data, total_test_data);
	println("\n\nData Loaded. Training examples:"<<total_train_data/N<<" Testing examples:"<<total_test_data/N<<" Data dimension:"<<N);

	// Shuffle training data
	int m = total_train_data/N;
	int n = total_test_data/N;
	int *perm = new int[m];
	for (int i=0; i<m; i++) perm[i] = i;
	std::random_shuffle(&perm[0],&perm[m]);

	// apply the permutation
	train_data = new value_type[m*N];
	train_target = new value_type[m];
	for (int i=0; i<m; i++){
		for (int j=0; j<N; j++){
			train_data[i*N+j] = temp_training_data[perm[i]*N+j];
		}
		train_target[i] = temp_training_target[perm[i]];
	}
	println("Training Examples shuffled.");

	// Free some variables
	delete [] temp_training_data;
	delete [] temp_training_target;
	delete [] perm;

	// Normalizing input data by dividing by 255
	for (int i=0; i<total_train_data; i++)
		train_data[i] /= 255;
	for (int i=0; i<total_test_data; i++)
		testing_data[i] /= 255;

	// Copy training and testing data to device memory
	value_type* train_data_d = NULL;
	checkCudaErrors( cudaMalloc(&train_data_d, MSIZE(total_train_data)) );
	checkCudaErrors( cudaMemcpy(train_data_d, train_data, MSIZE(total_train_data), cudaMemcpyHostToDevice) );

	value_type* testing_data_d = NULL;
	checkCudaErrors( cudaMalloc(&testing_data_d, MSIZE(total_test_data)) );	
	checkCudaErrors( cudaMemcpy(testing_data_d, testing_data, MSIZE(total_test_data), cudaMemcpyHostToDevice) );

	value_type* train_target_d = NULL;
	checkCudaErrors( cudaMalloc(&train_target_d, MSIZE(m)) );	
	checkCudaErrors( cudaMemcpy(train_target_d, train_target, MSIZE(m), cudaMemcpyHostToDevice) );

	// Try to load learned weights from file other wise start learning phase
	if (LOAD_DATA)
	{
		COPY_DATA_TO_DEVICE

		println("Weights from file loaded");
		// Testing Phase
		{
			print("\nTesting : \tBatch size: "<<batch_size<<"\t");
			std::clock_t    start;
			start = std::clock(); 
			int correct = 0;
			
			for (int i=0; i<n; i+=batch_size){
				if (i+batch_size<=n){
					value_type* target = testing_target+i;
					value_type predicted[batch_size];
					
					mnist.predict_example(testing_data_d + i*N, LAYER_NAMES, predicted, batch_size);
					
					for (int j = 0; j < batch_size; ++j)
						if (target[j] == predicted[j]){
							correct++;
						}
					if (!DEBUG && i%1000==0) print("."<<std::flush);
					// println("Example: "<<i<<"\tTarget: "<<target<<"\tPredicted: "<<predicted);
				}else{
					println("Skipping "<<(n-i)<<" examples.");
				}
			}
			println("\tTime: " << (std::clock() - start) / (double)(CLOCKS_PER_SEC) << " second");
			println("Accuracy: "<<((100.0 * correct)/n)<<" %\t\tCorrectly predicted "<<correct<<" examples out of "<<n);
		}
	}
	else{
		println("\n **** Learning started ****");
		std::clock_t    start;
		start = std::clock(); 

		// Learn all examples till convergence
		int max_iterations = 50, iterations = 0, best_correct = 0;
		while(iterations++ < max_iterations ){ // TODO: Use a better convergence criteria
			// Training Iteration
			{
				learning_rate = base_learning_rate*pow((1.0+base_gamma*(iterations-1)), -base_power);
				print("\nLearning ("<<iterations<<") : ");
				print("learning rate: "<<learning_rate<<"\tBatch Size: "<<batch_size<<"\t");
				std::clock_t    start;
				start = std::clock();
				for (int i=0; i<m; i+=batch_size){
					if (i+batch_size<=m){
						if (DEBUG) print("\n\n\n\n\n");
						value_type* targets = train_target_d+i;
						
						mnist.learn_example(train_data_d +i*N, LAYER_NAMES, targets, batch_size);

						if (DEBUG) getchar();
						else if (i%1000==0) print("."<<std::flush);
						//println("Example "<<i<<" learned. "<<"\tTarget: "<<target<<"\tPredicted: "<<predicted);
					}else{
						println("Skipping "<<(m-i)<<" examples.");
					}
				}
				println("\tTime: " << (std::clock() - start) / (double)(CLOCKS_PER_SEC) << " second");
			}

			COPY_DATA_TO_HOST
			// Save the weights in a binary file
			if (SAVE_DATA)
				println("Weights Saved after "<<iterations<<" iterations.");

			// Testing Phase
			{
				print("\nTesting ("<<iterations<<") : ");
				std::clock_t    start;
				start = std::clock(); 
				int correct = 0;
				for (int i=0; i<n; i+=batch_size){
					if (i+batch_size<=n){
						value_type* target = testing_target+i;
						value_type predicted[batch_size];
						
						mnist.predict_example(testing_data_d + i*N, LAYER_NAMES, predicted, batch_size);
						
						for (int j=0; j<batch_size; j++)
							if (target[j] == predicted[j]){
								correct++;
							}
						if (!DEBUG && i%1000==0) print("."<<std::flush);
						// println("Example: "<<i<<"\tTarget: "<<target<<"\tPredicted: "<<predicted);
					}else{
						println("Skipping "<<(n-i)<<" examples.");	
					}
				}
				
				println("\tTime: " << (std::clock() - start) / (double)(CLOCKS_PER_SEC) << " second");
				println("Accuracy: "<<((100.0 * correct)/n)<<" %\t\tCorrectly predicted "<<correct<<" examples out of "<<n);
				if (correct<best_correct){
					println("Accuracy started to decrease. Stopping Learning!! "<<correct-best_correct<<" misclassified.");
					// break;
				}
				print("Correctly classified "<<(correct-best_correct)<<" new examples. ");
				best_correct = correct;
				
				COPY_DATA_TO_HOST
				// Save the weights in a binary file
				if (SAVE_DATA)
					println("Weights Saved.");
			}
		}
		
		println("\n **** Learning completed ****");
		println("Total Time: " << (std::clock() - start) / (double)(CLOCKS_PER_SEC) << " second");
	}
	checkCudaErrors( cudaFree(testing_data_d) );
	checkCudaErrors( cudaFree(train_data_d) );
	checkCudaErrors( cudaFree(train_target_d) );
}

void readJPGImage(std::string jpgfile, MATRIX_DATA_TYPE* imageData_h){
	FIBITMAP *bitmap = FreeImage_Load(FIF_JPEG, jpgfile.c_str(), JPEG_ACCURATE);

	if (bitmap) {
		// Allocate a raw buffer
		int width = FreeImage_GetWidth(bitmap);
		int height = FreeImage_GetHeight(bitmap);
		int scan_width = FreeImage_GetPitch(bitmap);
		BYTE *bits = (BYTE*)malloc(height * scan_width);
		int c = scan_width/width;
		int d = 8*c;
		println(width<<" "<<height<<" "<<scan_width<<" "<<c<<" "<<d);
		// convert the bitmap to raw bits (top-left pixel first)
		FreeImage_ConvertToRawBits(bits, bitmap, scan_width, d, FI_RGBA_RED_MASK, FI_RGBA_GREEN_MASK, FI_RGBA_BLUE_MASK, TRUE);

		for (int i=0; i<c; i++){
			for (int j=0; j<height; j++){
				for (int k=0; k<width; k++){
					imageData_h[width*height*i + j*width + k] = bits[j*scan_width + k*c + i]/255.0;
				}
			}
		}
		FreeImage_Unload(bitmap);
	}
}
/******************************************************************************
 * MAIN() function
 *****************************************************************************/

int main(int argc, char *argv[])
{   
	// Print Usage if help is in the arguments
	if (checkCmdLineFlag(argc, (const char **)argv, "help"))
	{
		displayUsage();
		exit(EXIT_WAIVED); 
	}
	

	// MATRIX_DATA_TYPE imageData_h[255*255*3];
	// std::string jpgfile("/home/abhishek/Desktop/partition/dataset/bval/ILSVRC2010_val_00008001.JPEG");

	// readJPGImage(jpgfile, imageData_h);
	
	// for (int i=0; i<3; i++){
	// 	println(i<<": \n");
	// 	for (int j=0; j<4; j++){
	// 		for (int k=0; k<4; k++){
	// 			print((int)(imageData_h[255*255*i + j*255 + k]*255)<<" ");
	// 		}
	// 		println(" ");
	// 	}
	// }

	// Print Library and Device stats
	int version = (int)cudnnGetVersion();
	printf("\n\nCuDNN Version : %d , CUDNN_VERSION from cudnn.h : %d (%s)\n", version, CUDNN_VERSION, CUDNN_VERSION_STR);
	printf("Host compiler version : %s %s\r", COMPILER_NAME, COMPILER_VER);
	showDevices();

	// If device argument is provided then set device (device=1)
	int device = 0;
	if (checkCmdLineFlag(argc, (const char **)argv, "device"))
	{
		device = getCmdLineArgumentInt(argc, (const char **)argv, "device");
		checkCudaErrors( cudaSetDevice(device) );
	}
	println("Using device " << device);


	srand(time(NULL));

	run_mnist();

	// Reset device and exit gracefully
	cudaDeviceReset();
	exit(EXIT_SUCCESS);        
}
