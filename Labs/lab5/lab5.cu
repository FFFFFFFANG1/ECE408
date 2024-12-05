// MP5 Reduction
// Input: A num list of length n
// Output: Sum of the list = list[0] + list[1] + ... + list[n-1];

#include <wb.h>

#define BLOCK_SIZE 512 //@@ This value is not fixed and you can adjust it according to the situation

#define wbCheck(stmt)                                                     \
  do {                                                                    \
    cudaError_t err = stmt;                                               \
    if (err != cudaSuccess) {                                             \
      wbLog(ERROR, "Failed to run stmt ", #stmt);                         \
      wbLog(ERROR, "Got CUDA error ...  ", cudaGetErrorString(err));      \
      return -1;                                                          \
    }                                                                     \
  } while (0)
  
__global__ void total(float *input, float *output, int len) {
  //@@ Load a segment of the input vector into shared memory
  //@@ Traverse the reduction tree
  //@@ Write the computed sum of the block to the output vector at the correct index
  __shared__ float partialSum[2 * BLOCK_SIZE];
  unsigned int tx = threadIdx.x;
  unsigned int start = 2 * blockIdx.x * blockDim.x;

  if (start + tx < len) {
    partialSum[tx] = input[start + tx];
  } else {
    partialSum[tx] = 0.0;
  }
  if (start + blockDim.x + tx < len) {
    partialSum[blockDim.x + tx] = input[start + blockDim.x + tx];
  } else {
    partialSum[blockDim.x + tx] = 0.0;
  }

  for (unsigned int stride = blockDim.x; stride > 0; stride /= 2) {
    __syncthreads();
    if (tx < stride) {
      partialSum[tx] += partialSum[tx + stride];
    }
  }
  
  if (tx == 0) {
    output[blockIdx.x] = partialSum[0];
  }
}

int main(int argc, char **argv) {
  int ii;
  wbArg_t args;
  float *hostInput;  // The input 1D list
  float *hostOutput; // The output list
  //@@ Initialize device input and output pointers

  int numInputElements;  // number of elements in the input list
  int numOutputElements; // number of elements in the output list

  args = wbArg_read(argc, argv);

  //Import data and create memory on host
  hostInput =
      (float *)wbImport(wbArg_getInputFile(args, 0), &numInputElements);

  numOutputElements = ceil(numInputElements / (float)BLOCK_SIZE);
  hostOutput = (float *)malloc(numOutputElements * sizeof(float));

  // The number of input elements in the input is numInputElements
  // The number of output elements in the input is numOutputElements

  //@@ Allocate GPU memory
  float *deviceInput;
  float *deviceOutput;
  cudaMalloc((void **)&deviceInput, numInputElements * sizeof(float));
  cudaMalloc((void **)&deviceOutput, numOutputElements * sizeof(float));

  //@@ Copy input memory to the GPU
  cudaMemcpy(deviceInput, hostInput, numInputElements * sizeof(float),
             cudaMemcpyHostToDevice);

  //@@ Initialize the grid and block dimensions here
  dim3 DimGrid(ceil(numInputElements/(float)BLOCK_SIZE), 1, 1);
  dim3 DimBlock(BLOCK_SIZE, 1, 1);

  //@@ Launch the GPU Kernel and perform CUDA computation
  total<<<DimGrid, DimBlock>>>(deviceInput, deviceOutput, numInputElements);
  
  cudaDeviceSynchronize();  
  //@@ Copy the GPU output memory back to the CPU
  cudaMemcpy(hostOutput, deviceOutput, numOutputElements * sizeof(float),
             cudaMemcpyDeviceToHost);
  
  /********************************************************************
   * Reduce output vector on the host
   * NOTE: One could also perform the reduction of the output vector
   * recursively and support any size input. 
   * For simplicity, we do not require that for this lab.
   ********************************************************************/
  for (ii = 1; ii < numOutputElements; ii++) {
    hostOutput[0] += hostOutput[ii];
  }

  //@@ Free the GPU memory
  cudaFree(deviceInput);
  cudaFree(deviceOutput);


  wbSolution(args, hostOutput, 1);

  free(hostInput);
  free(hostOutput);

  return 0;
}
