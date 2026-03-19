import GPUtil

# 获取所有GPU的使用情况
gpus = GPUtil.getGPUs()

# 输出GPU的详细信息
for gpu in gpus:
    print(f"GPU ID: {gpu.id}, Name: {gpu.name}")
    print(f"Load: {gpu.load*100} %")
    print(f"Free Memory: {gpu.memoryFree} MB")
    print(f"Used Memory: {gpu.memoryUsed} MB")
    print(f"Total Memory: {gpu.memoryTotal} MB")
    print(f"Temperature: {gpu.temperature} °C")
    print("---------------------------")
