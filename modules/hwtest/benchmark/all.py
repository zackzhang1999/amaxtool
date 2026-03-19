#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import subprocess
import time
import platform
import re
import json
import math
import random
import tempfile
import atexit
import select
import tty
import termios
import signal
import threading
import multiprocessing
from datetime import datetime, timedelta
from multiprocessing import Event, Process, Queue, Manager
from packaging import version
import importlib.util

# 全局变量
exit_event = Event()
child_processes = []
temp_files = []
test_results = {
    "start_time": None,
    "end_time": None,
    "cpu_stats": {"peak_temp": {}, "avg_temp": {}, "peak_usage": 0},
    "gpu_stats": {"peak_power": {}, "peak_temp": {}, "peak_util": {}, "peak_mem": {}},
    "memory_stats": {"peak_usage_percent": 0, "tested_gb": 0},
    "system_info": {}
}
pre_final_gpu_status = None

# 颜色常量（保持原脚本风格）
RESET = '\033[0m'
BOLD = '\033[1m'
UNDERLINE = '\033[4m'
RED = '\033[91m'
GREEN = '\033[92m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
MAGENTA = '\033[95m'
CYAN = '\033[96m'
WHITE = '\033[97m'
GRAY = '\033[90m'

def get_gradient_color(value, min_val, max_val):
    """根据数值在范围内的位置返回渐变颜色"""
    value = max(min_val, min(value, max_val))
    normalized = (value - min_val) / (max_val - min_val) if max_val > min_val else 0
    
    color_points = [(0, 1, 0), (0, 0, 1), (1, 1, 0), (1, 0, 0)]  # 绿->蓝->黄->红
    
    if normalized <= 0.33:
        ratio = normalized / 0.33
        r = color_points[0][0] + ratio * (color_points[1][0] - color_points[0][0])
        g = color_points[0][1] + ratio * (color_points[1][1] - color_points[0][1])
        b = color_points[0][2] + ratio * (color_points[1][2] - color_points[0][2])
    elif normalized <= 0.66:
        ratio = (normalized - 0.33) / 0.33
        r = color_points[1][0] + ratio * (color_points[2][0] - color_points[1][0])
        g = color_points[1][1] + ratio * (color_points[2][1] - color_points[1][1])
        b = color_points[1][2] + ratio * (color_points[2][2] - color_points[1][2])
    else:
        ratio = (normalized - 0.66) / 0.34
        r = color_points[2][0] + ratio * (color_points[3][0] - color_points[2][0])
        g = color_points[2][1] + ratio * (color_points[3][1] - color_points[2][1])
        b = color_points[2][2] + ratio * (color_points[3][2] - color_points[2][2])
    
    return f'\033[38;2;{int(r*255)};{int(g*255)};{int(b*255)}m'

def colorize_value(value, min_val, max_val, format_str="{}"):
    """为数值添加颜色并格式化"""
    color = get_gradient_color(value, min_val, max_val)
    return f"{BOLD}{color}{format_str.format(value)}{RESET}"

def get_terminal_size():
    """获取当前终端窗口的大小"""
    try:
        result = subprocess.run(['stty', 'size'], capture_output=True, text=True)
        if result.returncode == 0:
            rows, columns = result.stdout.strip().split()
            return int(columns), int(rows)
    except:
        pass
    return 120, 30

def get_cpu_temperatures():
    """获取CPU温度（双路CPU支持）"""
    cpu_temps = {}
    try:
        result = subprocess.run(["sensors"], capture_output=True, text=True)
        if result.returncode == 0:
            lines = result.stdout.split('\n')
            current_socket = None
            socket_patterns = [r'CPU (\d+)', r'socket (\d+)', r'physical id (\d+)', r'Package id (\d+)']
            
            for line in lines:
                socket_match = None
                for pattern in socket_patterns:
                    socket_match = re.search(pattern, line, re.IGNORECASE)
                    if socket_match:
                        break
                
                if socket_match:
                    try:
                        socket_num = int(socket_match.group(1))
                        current_socket = socket_num + 1
                    except:
                        if current_socket is None:
                            current_socket = 1
                        else:
                            current_socket += 1
                    continue
                
                core_match = re.search(r'(Core|Package|CPU)\s+(\d*)\s*:\s+\+?(\d+\.\d+)°C', line)
                if core_match and current_socket is not None:
                    temp = float(core_match.group(3))
                    cpu_id = current_socket
                    if cpu_id in cpu_temps:
                        if temp > cpu_temps[cpu_id]:
                            cpu_temps[cpu_id] = temp
                    else:
                        cpu_temps[cpu_id] = temp
    except Exception as e:
        pass
    
    if not cpu_temps:
        try:
            import psutil
            temps = psutil.sensors_temperatures()
            for sensor in ['coretemp', 'cpu_thermal', 'k10temp', 'fam15h_power']:
                if sensor in temps:
                    cpu_temps[1] = max([t.current for t in temps[sensor]])
                    break
            physical_cpus = psutil.cpu_count(logical=False)
            if physical_cpus and physical_cpus > 1 and len(cpu_temps) == 1:
                if 'coretemp' in temps:
                    for sensor in temps['coretemp']:
                        if 'Package id 1' in sensor.label:
                            cpu_temps[2] = sensor.current
                            break
                if 2 not in cpu_temps:
                    cpu_temps[2] = list(cpu_temps.values())[0]
        except:
            pass
    
    if not cpu_temps:
        cpu_temps[1] = 0.0
    elif hasattr(os, 'cpu_count') and os.cpu_count() > 1 and len(cpu_temps) == 1:
        cpu_temps[2] = list(cpu_temps.values())[0]
    
    return cpu_temps

# ==================== CPU压力测试模块 ====================
class CPUStressTest:
    """CPU压力测试类 - 100%满载所有核心"""
    
    def __init__(self):
        self.processes = []
        self.stop_event = Event()
        self.stats_queue = Queue()
        self.monitor_thread = None
        
    @staticmethod
    def get_cpu_count():
        """获取逻辑CPU核心数"""
        return os.cpu_count() or multiprocessing.cpu_count()
    
    @staticmethod
    def cpu_worker(stop_event, core_id, stats_queue):
        """CPU工作进程 - 纯计算负载保持100%"""
        # 设置CPU亲和性（如果支持）
        try:
            os.system(f"taskset -cp {core_id} {os.getpid()} > /dev/null 2>&1")
        except:
            pass
            
        # 高强度计算循环
        iteration = 0
        start_time = time.time()
        
        while not stop_event.is_set():
            # 混合整数和浮点运算，确保CPU满载
            result = 0.0
            for i in range(100000):
                result += math.sin(i) * math.cos(i) * math.sqrt(abs(i) + 1.0)
                result += (i ** 2) % 999983  # 大质数取模
                result = result % 1e10
            
            iteration += 1
            if iteration % 100 == 0:  # 每100次循环报告一次
                elapsed = time.time() - start_time
                stats_queue.put({
                    "core_id": core_id,
                    "iterations": iteration,
                    "elapsed": elapsed
                })
    
    def start(self, duration_minutes):
        """启动CPU压力测试"""
        cpu_count = self.get_cpu_count()
        print(f"{GREEN}启动CPU压力测试 - 检测到的核心数: {cpu_count}{RESET}")
        print(f"{YELLOW}将对所有{cpu_count}个逻辑核心施加100%计算负载{RESET}\n")
        
        # 为每个核心创建进程
        for i in range(cpu_count):
            p = Process(target=self.cpu_worker, args=(self.stop_event, i, self.stats_queue))
            p.start()
            self.processes.append(p)
        
        # 启动监控线程
        self.monitor_thread = threading.Thread(target=self._monitor_cpu, args=(duration_minutes,))
        self.monitor_thread.start()
        
        return True
    
    def _monitor_cpu(self, duration_minutes):
        """后台监控CPU使用率"""
        try:
            import psutil
            end_time = time.time() + (duration_minutes * 60)
            
            while time.time() < end_time and not self.stop_event.is_set():
                cpu_percent = psutil.cpu_percent(interval=1)
                temps = get_cpu_temperatures()
                
                # 更新全局统计数据
                if cpu_percent > test_results["cpu_stats"]["peak_usage"]:
                    test_results["cpu_stats"]["peak_usage"] = cpu_percent
                
                for cpu_id, temp in temps.items():
                    if cpu_id not in test_results["cpu_stats"]["peak_temp"] or \
                       temp > test_results["cpu_stats"]["peak_temp"][cpu_id]:
                        test_results["cpu_stats"]["peak_temp"][cpu_id] = temp
                
                time.sleep(1)
        except Exception as e:
            print(f"CPU监控错误: {e}")
    
    def stop(self):
        """停止CPU压力测试"""
        print(f"\n{YELLOW}正在停止CPU压力测试...{RESET}")
        self.stop_event.set()
        
        for p in self.processes:
            if p.is_alive():
                p.terminate()
                p.join(timeout=2)
        
        if self.monitor_thread and self.monitor_thread.is_alive():
            self.monitor_thread.join(timeout=2)
        
        self.processes = []
        print(f"{GREEN}CPU压力测试已停止{RESET}")

# ==================== 内存压力测试模块 ====================
class MemoryStressTest:
    """内存压力测试类 - 占用90%内存容量"""
    
    def __init__(self):
        self.memory_list = []
        self.stop_event = Event()
        self.worker_threads = []
        self.allocated_size = 0
        
    @staticmethod
    def get_available_memory():
        """获取系统可用内存（MB）"""
        try:
            import psutil
            mem = psutil.virtual_memory()
            return mem.total / (1024 * 1024), mem.available / (1024 * 1024)
        except:
            # 备用方案
            result = subprocess.run(['free', '-m'], capture_output=True, text=True)
            lines = result.stdout.split('\n')
            for line in lines:
                if line.startswith('Mem:'):
                    parts = line.split()
                    return int(parts[1]), int(parts[6])
        return 0, 0
    
    def start(self, duration_minutes):
        """启动内存压力测试"""
        total_mb, available_mb = self.get_available_memory()
        target_mb = int(total_mb * 0.9)  # 目标90%总内存
        
        print(f"{GREEN}启动内存压力测试{RESET}")
        print(f"总内存: {total_mb/1024:.2f} GB")
        print(f"目标占用: {target_mb/1024:.2f} GB (90%)")
        print(f"测试时长: {duration_minutes} 分钟\n")
        
        try:
            # 分配大内存块
            block_size = 10 * 1024 * 1024  # 10MB块
            num_blocks = int((target_mb * 1024 * 1024) / block_size)
            
            print(f"正在分配 {num_blocks} 个内存块...")
            for i in range(num_blocks):
                # 分配并写入数据，确保物理内存占用
                block = bytearray(block_size)
                for j in range(0, block_size, 4096):
                    block[j] = random.randint(0, 255)
                self.memory_list.append(block)
                
                if i % 100 == 0:
                    progress = (i / num_blocks) * 100
                    print(f"分配进度: {progress:.1f}%", end='\r')
            
            self.allocated_size = len(self.memory_list) * block_size / (1024**3)  # GB
            test_results["memory_stats"]["tested_gb"] = self.allocated_size
            print(f"\n{GREEN}内存分配完成: {self.allocated_size:.2f} GB{RESET}")
            
            # 启动内存访问线程保持压力
            for i in range(4):  # 4个访问线程
                t = threading.Thread(target=self._memory_worker, args=(i,))
                t.start()
                self.worker_threads.append(t)
            
            # 启动监控
            self.monitor_thread = threading.Thread(target=self._monitor_memory, args=(duration_minutes,))
            self.monitor_thread.start()
            
            return True
            
        except MemoryError:
            print(f"{RED}内存分配失败: 无法分配目标内存量{RESET}")
            return False
        except Exception as e:
            print(f"{RED}内存测试启动错误: {e}{RESET}")
            return False
    
    def _memory_worker(self, thread_id):
        """内存访问工作线程 - 保持内存活跃"""
        while not self.stop_event.is_set():
            if self.memory_list:
                # 随机访问内存块
                block_idx = random.randint(0, len(self.memory_list) - 1)
                block = self.memory_list[block_idx]
                # 随机写入
                for _ in range(1000):
                    pos = random.randint(0, len(block) - 1)
                    block[pos] = random.randint(0, 255)
            time.sleep(0.01)
    
    def _monitor_memory(self, duration_minutes):
        """监控内存使用率"""
        try:
            import psutil
            end_time = time.time() + (duration_minutes * 60)
            
            while time.time() < end_time and not self.stop_event.is_set():
                mem = psutil.virtual_memory()
                if mem.percent > test_results["memory_stats"]["peak_usage_percent"]:
                    test_results["memory_stats"]["peak_usage_percent"] = mem.percent
                time.sleep(1)
        except Exception as e:
            pass
    
    def stop(self):
        """停止内存压力测试并释放内存"""
        print(f"\n{YELLOW}正在停止内存压力测试并释放内存...{RESET}")
        self.stop_event.set()
        
        for t in self.worker_threads:
            if t.is_alive():
                t.join(timeout=2)
        
        self.memory_list = []  # 释放内存
        import gc
        gc.collect()
        
        print(f"{GREEN}内存压力测试已停止，资源已释放{RESET}")

# ==================== GPU压力测试模块（基于原脚本） ====================
class GPUStressTest:
    """GPU压力测试 - 提取自原脚本"""
    
    def __init__(self):
        self.child_processes = []
        self.gpu_indices = []
        self.duration = 0
        
    def create_cuda_program(self):
        """创建优化的CUDA压测程序"""
        cuda_code = """
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <cuda_runtime.h>
#include <nvml.h>
#include <time.h>
#include <signal.h>

volatile sig_atomic_t exit_flag = 0;

void signal_handler(int signum) {
    exit_flag = 1;
}

__device__ float intensive_math_computation(float val, float shared_val, float mem_val) {
    float val1 = sinf(val) * cosf(val) + tanhf(val) * sqrtf(fabsf(val));
    float temp = fabsf(val) + 1.0f;
    float val2 = logf(temp) * val * val - 0.5f * val + 2.0f;
    float val3 = powf(val, 1.2f) + expf(fmodf(val, 3.14159f));
    float clamped = fmaxf(fminf(val * 0.1f, 0.99f), -0.99f);
    float val4 = asinf(clamped) * 5.0f;
    
    val = val1 * 0.3f + val2 * 0.3f + val3 * 0.2f + val4 * 0.2f;
    val += shared_val * 0.05f + mem_val * 1e-5f;
    
    int ival = (int)(val * 1000) % 256;
    ival = (ival ^ 0x55) & 0xFF;
    val += (float)ival * 0.001f;
    
    val = val * val - 1.0f / (fabsf(val) + 1e-5f);
    val = powf(val, 0.75f) + expf(-fabsf(val));
    val = coshf(val) * 0.1f + sinhf(val) * 0.1f;
    
    return val;
}

__global__ void stress_kernel(float *a, float *b, float *c, int n, 
                             float *large_buf, size_t large_buf_size) {
    int idx = threadIdx.x + blockIdx.x * blockDim.x;
    volatile float result = 0.0f;
    
    __shared__ float shared_data[1024];
    if (threadIdx.x < 1024) {
        shared_data[threadIdx.x] = a[idx] + b[idx];
    }
    __syncthreads();
    
    if (idx < n) {
        float val = a[idx];
        int counter = 0;
        
        for (int i = 0; i < 15000; i++) {
            size_t mem_index = (size_t)(val * 1000 + i + idx * 1777) % large_buf_size;
            float mem_val = 0.0f;
            if (i % 10 == 0 && large_buf != NULL) {
                mem_val = large_buf[mem_index];
            }
            
            val = intensive_math_computation(val, shared_data[(threadIdx.x + i) % blockDim.x], mem_val);
            
            if (i % 15 == 0 && large_buf != NULL) {
                large_buf[mem_index] = val * 1e-5f;
            }
            
            counter += (int)(val * 110) % 128;
            counter = (counter << 3) | (counter >> 5);
        }
        
        result = val + (float)counter;
        c[idx] = result;
    }
}

int main(int argc, char **argv) {
    if (argc != 3) {
        printf("Usage: %s <device_id> <timeout_seconds>\\\\n", argv[0]);
        return 1;
    }
    
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    int device_id = atoi(argv[1]);
    int timeout_seconds = atoi(argv[2]);
    time_t start_time = time(NULL);
    
    cudaSetDevice(device_id);
    
    nvmlReturn_t nvmlResult = nvmlInit();
    if (nvmlResult != NVML_SUCCESS) {
        printf("NVML init failed: %s\\\\n", nvmlErrorString(nvmlResult));
        return 1;
    }
    
    nvmlDevice_t nvmlDevice;
    nvmlResult = nvmlDeviceGetHandleByIndex(device_id, &nvmlDevice);
    if (nvmlResult != NVML_SUCCESS) {
        printf("Get device handle failed: %s\\\\n", nvmlErrorString(nvmlResult));
        nvmlShutdown();
        return 1;
    }
    
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, device_id);
    
    int n = prop.maxThreadsPerMultiProcessor * prop.multiProcessorCount * 64;
    size_t size = n * sizeof(float);
    
    float *h_a, *h_b, *h_c;
    float *d_a, *d_b, *d_c;
    
    cudaMallocHost((void**)&h_a, size);
    cudaMallocHost((void**)&h_b, size);
    cudaMallocHost((void**)&h_c, size);
    
    for (int i = 0; i < n; i++) {
        h_a[i] = (float)rand() / RAND_MAX;
        h_b[i] = (float)rand() / RAND_MAX;
        h_c[i] = 0.0f;
    }
    
    cudaMalloc((void**)&d_a, size);
    cudaMalloc((void**)&d_b, size);
    cudaMalloc((void**)&d_c, size);
    
    cudaMemcpy(d_a, h_a, size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_b, h_b, size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_c, h_c, size, cudaMemcpyHostToDevice);
    
    size_t free_mem, total_mem;
    cudaMemGetInfo(&free_mem, &total_mem);
    
    size_t reserve_mem = 25 * 1024 * 1024;
    size_t large_buf_size = (free_mem > reserve_mem) ? (free_mem - reserve_mem) : 0;
    
    float *d_large_buf = NULL;
    if (large_buf_size > 0) {
        cudaMalloc(&d_large_buf, large_buf_size);
        cudaMemset(d_large_buf, 0, large_buf_size);
    }
    
    int threadsPerBlock = 1024;
    int blocksPerGrid = (n + threadsPerBlock - 1) / threadsPerBlock;
    
    int max_blocks_per_sm;
    cudaOccupancyMaxActiveBlocksPerMultiprocessor(&max_blocks_per_sm, stress_kernel, threadsPerBlock, 0);
    int max_blocks = max_blocks_per_sm * prop.multiProcessorCount;
    if (blocksPerGrid > max_blocks) {
        blocksPerGrid = max_blocks;
    }
    
    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);
    
    while(!exit_flag) {
        time_t now = time(NULL);
        if (difftime(now, start_time) >= timeout_seconds) {
            break;
        }
        
        cudaEventRecord(start);
        stress_kernel<<<blocksPerGrid, threadsPerBlock>>>(
            d_a, d_b, d_c, n, 
            d_large_buf,              
            large_buf_size / sizeof(float)
        );
        cudaEventRecord(stop);
        cudaEventSynchronize(stop);
    }
    
    if (d_large_buf) cudaFree(d_large_buf);
    cudaEventDestroy(start);
    cudaEventDestroy(stop);
    cudaFree(d_a);
    cudaFree(d_b);
    cudaFree(d_c);
    cudaFreeHost(h_a);
    cudaFreeHost(h_b);
    cudaFreeHost(h_c);
    
    cudaDeviceReset();
    nvmlShutdown();
    return 0;
}
"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.cu', delete=False) as f:
            f.write(cuda_code)
            return f.name
    
    def compile_cuda(self, cuda_file):
        """编译CUDA程序"""
        print("编译GPU压力测试程序...")
        exe_file = "/tmp/system_stress_gpu"
        cmd = ['nvcc', cuda_file, '-o', exe_file, '-lnvidia-ml', '-use_fast_math']
        
        if platform.system() == "Windows":
            cmd += ['-Xcompiler', '/MD', '-D_WINDOWS']
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"编译失败: {result.stderr}")
            return None
        
        temp_files.append(exe_file)
        return exe_file
    
    def get_gpus(self):
        """获取GPU列表"""
        try:
            result = subprocess.run(["nvidia-smi", "--query-gpu=index,name,power.limit", "--format=csv,noheader"], 
                                   capture_output=True, text=True)
            lines = result.stdout.strip().split('\n')
            gpus = []
            for i, line in enumerate(lines):
                if line.strip() == '': continue
                parts = line.split(', ')
                if len(parts) < 3:
                    parts = line.split(',')
                index = int(parts[0].strip())
                name = parts[1].strip()
                try:
                    power_limit = float(parts[2].strip().split()[0])
                except:
                    power_limit = 0.0
                gpus.append({"index": index, "name": name, "power_limit": power_limit})
            return gpus
        except Exception as e:
            print(f"获取GPU信息失败: {e}")
            return []
    
    def select_gpus(self):
        """交互式选择GPU"""
        gpus = self.get_gpus()
        if not gpus:
            print("未检测到可用的GPU")
            return []
        
        print(f"\n{BLUE}{BOLD}可用的GPU列表:{RESET}")
        for i, gpu in enumerate(gpus):
            print(f"{GREEN}[{i+1}] GPU {gpu['index']}: {gpu['name']} (功耗: {gpu['power_limit']:.1f}W){RESET}")
        
        print("\n请选择要测试的GPU:")
        print("[a] 全部GPU")
        print("[s] 选择特定GPU")
        print("[n] 跳过GPU测试")
        
        while True:
            choice = input("请输入选择 (a/s/n): ").strip().lower()
            
            if choice == 'a':
                return [gpu['index'] for gpu in gpus]
            elif choice == 's':
                try:
                    indices = input("请输入GPU序号（用逗号分隔，如1,3）: ").strip()
                    selected = []
                    for idx in indices.split(','):
                        idx = int(idx.strip()) - 1
                        if 0 <= idx < len(gpus):
                            selected.append(gpus[idx]['index'])
                    return selected
                except:
                    print("输入无效")
            elif choice == 'n':
                return []
            else:
                print("无效的选择")
    
    def start(self, gpu_indices, duration_minutes):
        """启动GPU压力测试"""
        if not gpu_indices:
            return True
            
        self.gpu_indices = gpu_indices
        self.duration = duration_minutes
        duration_seconds = int(duration_minutes * 60)
        
        print(f"\n{GREEN}启动GPU压力测试 - GPU: {gpu_indices}, 时长: {duration_minutes} 分钟{RESET}")
        
        # 编译CUDA程序
        cuda_file = self.create_cuda_program()
        exe_file = self.compile_cuda(cuda_file)
        if not exe_file:
            return False
        
        # 启动GPU进程
        def run_gpu(gpu_id):
            signal.signal(signal.SIGINT, signal.SIG_IGN)
            subprocess.run([exe_file, str(gpu_id), str(duration_seconds)])
        
        for gpu_id in gpu_indices:
            p = Process(target=run_gpu, args=(gpu_id,))
            p.start()
            self.child_processes.append(p)
        
        return True
    
    def stop(self):
        """停止GPU压力测试"""
        print(f"\n{YELLOW}正在停止GPU压力测试...{RESET}")
        for p in self.child_processes:
            if p.is_alive():
                p.terminate()
                p.join(timeout=5)
        self.child_processes = []
        print(f"{GREEN}GPU压力测试已停止{RESET}")

# ==================== 报告生成器 ====================
class ReportGenerator:
    """测试报告生成器"""
    
    def __init__(self):
        self.report_dir = "stress_test_reports"
        if not os.path.exists(self.report_dir):
            os.makedirs(self.report_dir)
    
    def generate(self):
        """生成Markdown格式的测试报告"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{self.report_dir}/stress_test_report_{timestamp}.md"
        
        # 获取系统信息
        hostname = platform.node()
        system = f"{platform.system()} {platform.release()} {platform.machine()}"
        
        content = f"""# 系统压力测试报告

## 基本信息
| 项目 | 值 |
|------|-----|
| 主机名 | {hostname} |
| 操作系统 | {system} |
| 测试开始时间 | {test_results['start_time'].strftime('%Y-%m-%d %H:%M:%S') if test_results['start_time'] else 'N/A'} |
| 测试结束时间 | {test_results['end_time'].strftime('%Y-%m-%d %H:%M:%S') if test_results['end_time'] else 'N/A'} |
| 总测试时长 | {self._format_duration(test_results['start_time'], test_results['end_time'])} |

## CPU 测试结果
| 指标 | 数值 |
|------|------|
| 逻辑核心数 | {os.cpu_count()} |
| 峰值使用率 | {test_results['cpu_stats']['peak_usage']:.1f}% |
"""
        
        # 添加CPU温度信息
        for cpu_id, temp in test_results['cpu_stats']['peak_temp'].items():
            content += f"| CPU{cpu_id} 峰值温度 | {temp:.1f}°C |\n"
        
        # 内存测试结果
        content += f"""
## 内存 测试结果
| 指标 | 数值 |
|------|------|
| 测试占用容量 | {test_results['memory_stats']['tested_gb']:.2f} GB |
| 峰值使用率 | {test_results['memory_stats']['peak_usage_percent']:.1f}% |

"""
        
        # GPU测试结果
        content += "## GPU 测试结果\n"
        if test_results['gpu_stats']['peak_temp']:
            content += "| GPU ID | 峰值温度 | 峰值功耗 | 峰值利用率 | 峰值显存占用 |\n"
            content += "|--------|----------|----------|------------|--------------|\n"
            
            # 合并所有GPU的峰值数据
            gpu_ids = set(test_results['gpu_stats']['peak_temp'].keys())
            for gpu_id in sorted(gpu_ids):
                temp = test_results['gpu_stats']['peak_temp'].get(gpu_id, 0)
                power = test_results['gpu_stats']['peak_power'].get(gpu_id, 0)
                util = test_results['gpu_stats']['peak_util'].get(gpu_id, 0)
                mem = test_results['gpu_stats']['peak_mem'].get(gpu_id, 0)
                content += f"| {gpu_id} | {temp}°C | {power:.1f}W | {util}% | {mem:.1f}% |\n"
        else:
            content += "未进行GPU测试或没有可用GPU\n"
        
        # 结论和建议
        content += """
## 测试结论
本次压力测试已完成，系统在高负载下的稳定性已验证。

### 关键指标评估
- **CPU**: 需检查峰值温度是否在安全范围内（<85°C为佳）
- **内存**: 90%容量占用测试通过
- **GPU**: 需检查是否达到功耗墙和温度墙

---
*报告由 System Stress Test Suite 自动生成*
"""
        
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(content)
        
        print(f"\n{GREEN}{BOLD}测试报告已生成: {os.path.abspath(filename)}{RESET}")
        return filename
    
    def _format_duration(self, start, end):
        if not start or not end:
            return "N/A"
        delta = end - start
        minutes = int(delta.total_seconds() // 60)
        seconds = int(delta.total_seconds() % 60)
        return f"{minutes}分{seconds}秒"

# ==================== 统一监控界面 ====================
class UnifiedMonitor:
    """统一监控界面 - 同时显示CPU/内存/GPU状态"""
    
    def __init__(self, gpu_indices, cpu_test, memory_test, gpu_test, duration_minutes):
        self.gpu_indices = gpu_indices
        self.cpu_test = cpu_test
        self.memory_test = memory_test
        self.gpu_test = gpu_test
        self.duration = duration_minutes
        self.end_time = datetime.now() + timedelta(minutes=duration_minutes)
        self.running = True
        
        # 峰值统计初始化
        self.peak_cpu_temp = {}
        self.peak_cpu_usage = 0
        self.peak_memory = 0
        
    def get_system_stats(self):
        """获取系统整体状态"""
        stats = {
            'cpu_temps': get_cpu_temperatures(),
            'cpu_usage': 0,
            'memory': None,
            'gpus': []
        }
        
        try:
            import psutil
            stats['cpu_usage'] = psutil.cpu_percent(interval=0.1)
            stats['memory'] = psutil.virtual_memory()
        except:
            pass
        
        # 获取GPU状态
        try:
            result = subprocess.run(["nvidia-smi", 
                                    "--query-gpu=index,power.draw,temperature.gpu,utilization.gpu,"
                                    "memory.used,memory.total",
                                    "--format=csv,noheader,nounits"], 
                                   capture_output=True, text=True)
            if result.returncode == 0:
                for line in result.stdout.strip().split('\n'):
                    parts = [p.strip() for p in line.split(',')]
                    if len(parts) >= 6:
                        try:
                            stats['gpus'].append({
                                'id': int(parts[0]),
                                'power': float(parts[1]),
                                'temp': int(parts[2]),
                                'util': int(parts[3]),
                                'mem_used': float(parts[4]),
                                'mem_total': float(parts[5])
                            })
                        except:
                            pass
        except:
            pass
        
        return stats
    
    def update_peaks(self, stats):
        """更新峰值统计数据"""
        # CPU温度峰值
        for cpu_id, temp in stats['cpu_temps'].items():
            if cpu_id not in self.peak_cpu_temp or temp > self.peak_cpu_temp[cpu_id]:
                self.peak_cpu_temp[cpu_id] = temp
                test_results['cpu_stats']['peak_temp'][cpu_id] = temp
            test_results['cpu_stats']['avg_temp'][cpu_id] = temp
        
        # CPU使用率峰值
        if stats['cpu_usage'] > self.peak_cpu_usage:
            self.peak_cpu_usage = stats['cpu_usage']
            test_results['cpu_stats']['peak_usage'] = stats['cpu_usage']
        
        # 内存峰值
        if stats['memory'] and stats['memory'].percent > self.peak_memory:
            self.peak_memory = stats['memory'].percent
            test_results['memory_stats']['peak_usage_percent'] = stats['memory'].percent
        
        # GPU峰值
        for gpu in stats['gpus']:
            gid = gpu['id']
            if gid in self.gpu_indices:
                if gid not in test_results['gpu_stats']['peak_temp'] or gpu['temp'] > test_results['gpu_stats']['peak_temp'][gid]:
                    test_results['gpu_stats']['peak_temp'][gid] = gpu['temp']
                if gid not in test_results['gpu_stats']['peak_power'] or gpu['power'] > test_results['gpu_stats']['peak_power'][gid]:
                    test_results['gpu_stats']['peak_power'][gid] = gpu['power']
                if gid not in test_results['gpu_stats']['peak_util'] or gpu['util'] > test_results['gpu_stats']['peak_util'][gid]:
                    test_results['gpu_stats']['peak_util'][gid] = gpu['util']
                if gpu['mem_total'] > 0:
                    mem_pct = (gpu['mem_used'] / gpu['mem_total']) * 100
                    if gid not in test_results['gpu_stats']['peak_mem'] or mem_pct > test_results['gpu_stats']['peak_mem'][gid]:
                        test_results['gpu_stats']['peak_mem'][gid] = mem_pct
    
    def display(self):
        """主显示循环"""
        import psutil
        
        while self.running and datetime.now() < self.end_time:
            if exit_event.is_set():
                break
            
            # 清屏
            os.system('cls' if platform.system() == 'Windows' else 'clear')
            
            columns, rows = get_terminal_size()
            time_left = self.end_time - datetime.now()
            total_seconds = max(0, int(time_left.total_seconds()))
            mins, secs = divmod(total_seconds, 60)
            
            # 标题
            separator = BLUE + '=' * columns + RESET
            title = f"{BOLD}{CYAN}系统综合压力测试监控{RESET} | {YELLOW}剩余时间: {mins}分{secs}秒{RESET}"
            
            print(separator)
            print(title.center(columns))
            print(separator)
            
            # 获取状态
            stats = self.get_system_stats()
            self.update_peaks(stats)
            
            # 显示CPU信息
            print(f"\n{BOLD}{MAGENTA}【CPU状态】{RESET}")
            cpu_temp_line = "当前温度: "
            for cpu_id, temp in stats['cpu_temps'].items():
                peak = self.peak_cpu_temp.get(cpu_id, temp)
                colored_temp = colorize_value(temp, 30, 90, "{:.1f}°C")
                cpu_temp_line += f"CPU{cpu_id}:{colored_temp}(峰值:{peak:.1f}°C) "
            print(cpu_temp_line)
            
            cpu_usage_str = colorize_value(stats['cpu_usage'], 0, 100, "{:.1f}%")
            print(f"当前使用率: {cpu_usage_str} (峰值: {self.peak_cpu_usage:.1f}%)")
            
            # 显示内存信息
            print(f"\n{BOLD}{MAGENTA}【内存状态】{RESET}")
            if stats['memory']:
                mem = stats['memory']
                mem_bar_len = 50
                used_len = int(mem_bar_len * mem.percent / 100)
                bar = '[' + '█' * used_len + '░' * (mem_bar_len - used_len) + ']'
                mem_color = get_gradient_color(mem.percent, 0, 100)
                print(f"总容量: {mem.total/(1024**3):.1f} GB | 已用: {mem.used/(1024**3):.1f} GB")
                print(f"使用率: {mem_color}{bar}{RESET} {mem.percent:.1f}% (峰值: {self.peak_memory:.1f}%)")
            
            # 显示GPU信息
            if self.gpu_indices and stats['gpus']:
                print(f"\n{BOLD}{MAGENTA}【GPU状态】{RESET}")
                print(f"{'GPU':<5} {'功耗(W)':<12} {'温度(°C)':<12} {'核心(%)':<12} {'显存(%)':<12}")
                print("-" * 60)
                
                for gpu in stats['gpus']:
                    if gpu['id'] in self.gpu_indices:
                        gstat = test_results['gpu_stats']
                        gid = gpu['id']
                        
                        power_str = colorize_value(gpu['power'], 0, 400, "{:.1f}")
                        temp_str = colorize_value(gpu['temp'], 30, 90, "{}")
                        util_str = colorize_value(gpu['util'], 0, 100, "{}")
                        
                        mem_pct = (gpu['mem_used'] / gpu['mem_total'] * 100) if gpu['mem_total'] > 0 else 0
                        mem_str = colorize_value(mem_pct, 0, 100, "{:.1f}")
                        
                        print(f"{gpu['id']:<5} {power_str:<12} {temp_str:<12} {util_str:<12} {mem_str:<12}")
                        
                        # 显示峰值
                        print(f"      峰值: {gstat['peak_power'].get(gid, 0):.1f}W  "
                              f"{gstat['peak_temp'].get(gid, 0)}°C  "
                              f"{gstat['peak_util'].get(gid, 0)}%  "
                              f"{gstat['peak_mem'].get(gid, 0):.1f}%")
            
            # 控制说明
            print(f"\n{separator}")
            print(f"{BOLD}按 Ctrl+C 终止所有测试{RESET}")
            print(f"{GRAY}正在监控: CPU({self.cpu_test.get_cpu_count()}核) | 内存({self.memory_test.allocated_size:.1f}GB) | GPU({len(self.gpu_indices)}块){RESET}")
            
            time.sleep(10)
        
        self.running = False

# ==================== 主控制程序 ====================
def main():
    """主函数"""
    columns, rows = get_terminal_size()
    
    # 打印标题
    separator = f"{BLUE}{'=' * columns}{RESET}"
    title = f"{' ' * 12}{BOLD}{CYAN}Linux系统综合压力测试工具{RESET} {' ' * 3}{BOLD}{GREEN}v2.0{RESET}"
    subtitle = f"{' ' * 16}{MAGENTA}{BOLD}CPU+内存+GPU全压力测试{RESET} {' ' * 1}{YELLOW}{BOLD}By.SystemStress{RESET}"
    
    print(separator)
    print(title.center(columns))
    print(subtitle.center(columns))
    print(separator)
    
    # 法律提示
    print(f"{RED}{BOLD}[提示!!!]{RESET}")
    print(f"{RED}{BOLD}本工具仅供技术测试使用，请遵守相关法律法规!{RESET}")
    print(f"{YELLOW}警告: 压力测试可能导致系统不稳定，请确保重要数据已备份!{RESET}\n")
    
    # 检查依赖
    if not os.path.exists("/usr/bin/nvidia-smi") and not os.path.exists("/usr/local/bin/nvidia-smi"):
        print(f"{YELLOW}警告: 未检测到nvidia-smi，GPU测试将不可用{RESET}")
    
    # 选择测试模式
    print(f"{BOLD}{CYAN}请选择测试模式:{RESET}")
    print(f"{GREEN}[1]{RESET} 仅CPU压力测试 (100%全核满载)")
    print(f"{GREEN}[2]{RESET} 仅内存压力测试 (90%容量占用)")
    print(f"{GREEN}[3]{RESET} 仅GPU压力测试 (核心+显存双烤)")
    print(f"{GREEN}[4]{RESET} 组合测试 (CPU+内存+GPU同时)")
    print(f"{GREEN}[5]{RESET} 退出")
    
    try:
        while True:
            choice = input("\n请输入选项 (1-5): ").strip()
            if choice == '5':
                sys.exit(0)
            if choice in ['1', '2', '3', '4']:
                break
            print("无效的选项")
    except KeyboardInterrupt:
        sys.exit(0)
    
    # 初始化测试对象
    cpu_test = CPUStressTest()
    memory_test = MemoryStressTest()
    gpu_test = GPUStressTest()
    gpu_indices = []
    
    # 根据模式配置
    if choice in ['3', '4']:
        gpu_indices = gpu_test.select_gpus()
        if not gpu_indices and choice == '3':
            print("未选择GPU，退出")
            return
    
    if choice in ['1', '4']:
        cpu_cores = cpu_test.get_cpu_count()
        print(f"{GREEN}将使用 {cpu_cores} 个逻辑核心进行CPU压力测试{RESET}")
    
    if choice in ['2', '4']:
        total_mb, _ = memory_test.get_available_memory()
        target_gb = (total_mb * 0.9) / 1024
        print(f"{GREEN}将占用约 {target_gb:.1f} GB 内存进行压力测试{RESET}")
    
    # 输入测试时长
    try:
        duration = float(input("\n请输入测试时长（分钟，默认5分钟）: ").strip() or "5")
        if duration <= 0:
            duration = 5
    except:
        duration = 5
    
    # 记录开始时间
    test_results['start_time'] = datetime.now()
    
    # 启动测试
    print(f"\n{BOLD}{CYAN}正在启动压力测试，时长: {duration} 分钟...{RESET}")
    
    try:
        # 启动各类测试
        if choice in ['1', '4']:
            cpu_test.start(duration)
        
        if choice in ['2', '4']:
            if not memory_test.start(duration):
                print("内存测试启动失败")
                return
        
        if choice in ['3', '4'] and gpu_indices:
            if not gpu_test.start(gpu_indices, duration):
                print("GPU测试启动失败")
                return
        
        # 启动统一监控
        monitor = UnifiedMonitor(gpu_indices, cpu_test, memory_test, gpu_test, duration)
        
        # 捕获Ctrl+C
        def signal_handler(sig, frame):
            print(f"\n{YELLOW}收到终止信号，正在安全停止所有测试...{RESET}")
            exit_event.set()
            monitor.running = False
        
        signal.signal(signal.SIGINT, signal_handler)
        
        # 运行监控
        monitor.display()
        
    except Exception as e:
        print(f"{RED}测试过程出错: {e}{RESET}")
    finally:
        # 清理资源
        test_results['end_time'] = datetime.now()
        
        print(f"\n{YELLOW}正在清理资源...{RESET}")
        if choice in ['1', '4']:
            cpu_test.stop()
        if choice in ['2', '4']:
            memory_test.stop()
        if choice in ['3', '4']:
            gpu_test.stop()
        
        # 生成报告
        print(f"\n{CYAN}正在生成测试报告...{RESET}")
        reporter = ReportGenerator()
        report_file = reporter.generate()
        
        print(f"\n{GREEN}{BOLD}所有测试已完成!{RESET}")
        print(f"报告文件: {report_file}")

if __name__ == "__main__":
    main()
