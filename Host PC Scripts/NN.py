# This script is used to generate a Neural Network to classify the handwritten digits of the MNIST Dataset
# After downloading the dataset and creating the dataset the script proceeds to perform Quantization Aware Training (QAT) 
# QAT is necessary to maintain the accuracy of the network even after the floating point values have been converted to fixed point values
# The entire design in fixed point so it is necessary to convert the floating point values to fixed point values
# After QAT the script checks the accuracy of the netwrok after training it for 10 Epochs
# The final step is to store the fixed point values: weights, biases, scales and shifts
# The values are stored in various files per layer and in .bin and .npy formats with .txt files being used to view the values on text editors ( only for inputs)
import os
import math
import struct
import numpy as np

import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader
from torchvision import datasets, transforms


# ============================================================
# USER / HARDWARE CONFIGURATION
# ============================================================

SEED = 42

ARRAY_DIM = 4

# Your actual neural network
LAYER_DIMS = [784, 128, 64, 10]

# Hardware datatype
WEIGHT_BITS = 8
ACT_BITS = 8

WEIGHT_MIN = -128
WEIGHT_MAX = 127

# Your Array.v ultimately clamps outputs to:
ACT_MIN = 0
ACT_MAX = 127

# Accumulator / bias
ACC_BITS = 32

# Training
BATCH_SIZE = 128
EPOCHS = 10
LEARNING_RATE = 1e-3

# Number of calibration images
CALIBRATION_IMAGES = 1000

OUTPUT_DIR = "quantized_network"


# ============================================================
# REPRODUCIBILITY
# ============================================================

torch.manual_seed(SEED)
np.random.seed(SEED)

if torch.cuda.is_available():
    torch.cuda.manual_seed_all(SEED)

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

print("Device:", device)


# ============================================================
# FLOATING-POINT NETWORK
# ============================================================

class MNISTNetwork(nn.Module):

    def __init__(self):
        super().__init__()

        self.fc1 = nn.Linear(784, 128)
        self.fc2 = nn.Linear(128, 64)
        self.fc3 = nn.Linear(64, 10)

    def forward(self, x):

        x = x.view(x.size(0), 784)

        x = self.fc1(x)
        x = torch.relu(x)

        x = self.fc2(x)
        x = torch.relu(x)

        x = self.fc3(x)

        return x


# ============================================================
# DATASET
# ============================================================

# Keep MNIST pixels as 0..255 instead of normalizing to 0..1.
#
# This makes the quantized representation much closer to the
# actual hardware representation.
#
# Hardware:
#
#       pixel = 0 ... 255
#
# Your current RTL is signed 8-bit, however, so values >127
# cannot be represented as positive signed INT8.
#
# We therefore scale the input to 0...127 before hardware export.
# ============================================================

transform = transforms.ToTensor()

train_dataset = datasets.MNIST(
    root="./data",
    train=True,
    download=True,
    transform=transform
)

test_dataset = datasets.MNIST(
    root="./data",
    train=False,
    download=True,
    transform=transform
)

train_loader = DataLoader(
    train_dataset,
    batch_size=BATCH_SIZE,
    shuffle=True,
    num_workers=0
)

test_loader = DataLoader(
    test_dataset,
    batch_size=BATCH_SIZE,
    shuffle=False,
    num_workers=0
)


# ============================================================
# CREATE NETWORK
# ============================================================

model = MNISTNetwork().to(device)

print("\nNetwork:")
print(model)


# ============================================================
# TRAINING
# ============================================================

criterion = nn.CrossEntropyLoss()

optimizer = optim.Adam(
    model.parameters(),
    lr=LEARNING_RATE
)


print("\n================================================")
print("TRAINING")
print("================================================")

for epoch in range(EPOCHS):

    model.train()

    total_loss = 0.0
    correct = 0
    total = 0

    for images, labels in train_loader:

        images = images.to(device)
        labels = labels.to(device)

        # Original MNIST is 0..1.
        #
        # Convert to approximately the range used by hardware.
        #
        # 0.0 -> 0
        # 1.0 -> 127
        #
        # This avoids unsigned 8-bit values >127 because the
        # accelerator datapath currently uses signed 8-bit.
        images = images * 127.0

        optimizer.zero_grad()

        outputs = model(images)

        loss = criterion(outputs, labels)

        loss.backward()

        optimizer.step()

        total_loss += loss.item()

        _, predicted = outputs.max(1)

        total += labels.size(0)
        correct += predicted.eq(labels).sum().item()

    accuracy = 100.0 * correct / total

    print(
        f"Epoch [{epoch+1}/{EPOCHS}] "
        f"Loss={total_loss/len(train_loader):.4f} "
        f"Accuracy={accuracy:.2f}%"
    )


# ============================================================
# FLOAT MODEL TEST
# ============================================================

def evaluate_float(model):

    model.eval()

    correct = 0
    total = 0

    with torch.no_grad():

        for images, labels in test_loader:

            images = images.to(device)
            labels = labels.to(device)

            images = images * 127.0

            outputs = model(images)

            _, predicted = outputs.max(1)

            total += labels.size(0)

            correct += predicted.eq(labels).sum().item()

    return 100.0 * correct / total


float_accuracy = evaluate_float(model)

print("\nFloating point accuracy:",
      f"{float_accuracy:.2f}%")


# ============================================================
# CREATE OUTPUT DIRECTORY
# ============================================================

os.makedirs(OUTPUT_DIR, exist_ok=True)


# ============================================================
# QUANTIZATION UTILITIES
# ============================================================

def calculate_scale(x, qmax=127.0):

    max_abs = torch.max(torch.abs(x)).item()

    if max_abs == 0:
        return 1.0

    return max_abs / qmax


def quantize_symmetric(x, scale):

    q = torch.round(x / scale)

    q = torch.clamp(
        q,
        WEIGHT_MIN,
        WEIGHT_MAX
    )

    return q.to(torch.int8)


# ============================================================
# EXTRACT FLOAT PARAMETERS
# ============================================================

float_layers = [
    model.fc1,
    model.fc2,
    model.fc3
]


# ============================================================
# QUANTIZED PARAMETERS
# ============================================================

quantized_weights = []
quantized_biases = []

weight_scales = []


print("\n================================================")
print("WEIGHT QUANTIZATION")
print("================================================")


for layer_number, layer in enumerate(float_layers):

    weight = layer.weight.detach().cpu()

    bias = layer.bias.detach().cpu()

    # --------------------------------------------------------
    # Symmetric INT8 weight quantization
    # --------------------------------------------------------

    scale = calculate_scale(weight)

    q_weight = quantize_symmetric(
        weight,
        scale
    )

    # --------------------------------------------------------
    # Bias
    #
    # Hardware accumulator is INT32.
    #
    # For integer convolution / FC:
    #
    # accumulator =
    #
    #       sum(input_int8 * weight_int8)
    #
    # Bias must therefore be represented in the same integer
    # accumulator domain.
    #
    # We initially use:
    #
    #       bias_int32 = bias_float / output_scale
    #
    # where output_scale is determined during calibration.
    #
    # So bias conversion is done below after activation
    # calibration.
    # --------------------------------------------------------

    quantized_weights.append(q_weight)

    weight_scales.append(scale)

    print(
        f"Layer {layer_number}: "
        f"{tuple(weight.shape)} "
        f"scale={scale:.8f}"
    )


# ============================================================
# ACTIVATION CALIBRATION
# ============================================================

print("\n================================================")
print("ACTIVATION CALIBRATION")
print("================================================")


activation_max = [
    0.0,   # input
    0.0,   # layer 1
    0.0,   # layer 2
    0.0    # output
]


model.eval()

calibration_count = 0

with torch.no_grad():

    for images, labels in train_loader:

        images = images.to(device)

        images = images * 127.0

        x = images.view(images.size(0), 784)

        # Input
        activation_max[0] = max(
            activation_max[0],
            torch.max(torch.abs(x)).item()
        )

        # Layer 1
        x = model.fc1(x)

        x = torch.relu(x)

        activation_max[1] = max(
            activation_max[1],
            torch.max(torch.abs(x)).item()
        )

        # Layer 2
        x = model.fc2(x)

        x = torch.relu(x)

        activation_max[2] = max(
            activation_max[2],
            torch.max(torch.abs(x)).item()
        )

        # Layer 3
        x = model.fc3(x)

        activation_max[3] = max(
            activation_max[3],
            torch.max(torch.abs(x)).item()
        )

        calibration_count += images.size(0)

        if calibration_count >= CALIBRATION_IMAGES:
            break


# ============================================================
# ACTIVATION SCALES
# ============================================================

activation_scales = []

for i, maximum in enumerate(activation_max):

    if maximum == 0:
        scale = 1.0
    else:
        scale = maximum / 127.0

    activation_scales.append(scale)

    print(
        f"Activation {i}: "
        f"max={maximum:.8f} "
        f"scale={scale:.8f}"
    )


# ============================================================
# HARDWARE REQUANTIZATION PARAMETERS
# ============================================================

print("\n================================================")
print("HARDWARE M / SHIFT")
print("================================================")


def calculate_M_shift(input_scale,
                      weight_scale,
                      output_scale):

    # Floating point scale relationship:
    #
    # input_real  = input_int * input_scale
    # weight_real = weight_int * weight_scale
    #
    # accumulator:
    #
    # acc = sum(input_int * weight_int)
    #
    # Real result:
    #
    # result_real =
    #       acc * input_scale * weight_scale
    #
    # Desired output integer:
    #
    # output_int =
    #       result_real / output_scale
    #
    # Therefore:
    #
    # output_int =
    #
    # acc *
    # input_scale *
    # weight_scale /
    # output_scale
    #
    # Hardware does:
    #
    # output = (acc + bias) * M >> SHIFT
    #
    # So we approximate:
    #
    # M / 2^SHIFT =
    #
    # input_scale * weight_scale / output_scale

    real_multiplier = (
        input_scale *
        weight_scale /
        output_scale
    )

    if real_multiplier == 0:
        return 0, 0

    # Search for a shift giving a reasonably sized integer M.
    #
    # Your hardware M is 32 bits.
    # Keep M positive and comfortably below 2^31.

    best_M = 0
    best_shift = 0
    best_error = float("inf")

    for shift in range(0, 31):

        M_float = real_multiplier * (2 ** shift)

        if M_float <= 0:
            continue

        M = int(round(M_float))

        if M <= 0:
            continue

        if M >= 2**31:
            continue

        reconstructed = M / float(2 ** shift)

        error = abs(
            reconstructed -
            real_multiplier
        )

        if error < best_error:

            best_error = error
            best_M = M
            best_shift = shift

    return best_M, best_shift


M_values = []
shift_values = []


for layer in range(3):

    M, shift = calculate_M_shift(
        activation_scales[layer],
        weight_scales[layer],
        activation_scales[layer + 1]
    )

    M_values.append(M)
    shift_values.append(shift)

    print(
        f"Layer {layer}: "
        f"M={M} "
        f"SHIFT={shift}"
    )


# ============================================================
# BIAS QUANTIZATION
# ============================================================

print("\n================================================")
print("BIAS QUANTIZATION")
print("================================================")


for layer in range(3):

    # Bias is added BEFORE M/SHIFT in your Array.v:
    #
    # intr <= result_reg + bias_reg
    #
    # Therefore bias must use the accumulator's integer
    # scale.
    #
    # accumulator scale =
    #
    # input_scale * weight_scale
    #
    bias_scale = (
        activation_scales[layer] *
        weight_scales[layer]
    )

    bias_float = float_layers[layer].bias.detach().cpu()

    bias_int = torch.round(
        bias_float / bias_scale
    )

    bias_int = torch.clamp(
        bias_int,
        -(2**31),
        2**31 - 1
    ).to(torch.int32)

    quantized_biases.append(bias_int)

    print(
        f"Layer {layer}: "
        f"bias scale={bias_scale:.12e} "
        f"range=[{bias_int.min().item()}, "
        f"{bias_int.max().item()}]"
    )


# ============================================================
# SAVE NETWORK DESCRIPTION
# ============================================================

with open(
    os.path.join(OUTPUT_DIR, "network_config.txt"),
    "w"
) as f:

    f.write("MNIST SYSTOLIC ARRAY NETWORK\n")
    f.write("============================\n\n")

    f.write("Architecture:\n")
    f.write("784 -> 128 -> 64 -> 10\n\n")

    f.write("Array:\n")
    f.write("4 x 4\n\n")

    f.write("Datatype:\n")
    f.write("Weights: INT8\n")
    f.write("Activations: INT8 / unsigned-positive representation\n")
    f.write("Accumulator: INT32\n")
    f.write("Bias: INT32\n\n")

    for i in range(3):

        f.write(f"Layer {i}\n")

        f.write(
            f"Input features: "
            f"{LAYER_DIMS[i]}\n"
        )

        f.write(
            f"Output features: "
            f"{LAYER_DIMS[i+1]}\n"
        )

        f.write(
            f"NO_ADD: "
            f"{LAYER_DIMS[i]}\n"
        )

        f.write(
            f"Weight scale: "
            f"{weight_scales[i]:.12e}\n"
        )

        f.write(
            f"Input scale: "
            f"{activation_scales[i]:.12e}\n"
        )

        f.write(
            f"Output scale: "
            f"{activation_scales[i+1]:.12e}\n"
        )

        f.write(
            f"M: "
            f"{M_values[i]}\n"
        )

        f.write(
            f"SHIFT: "
            f"{shift_values[i]}\n\n"
        )


# ============================================================
# SAVE WEIGHTS
# ============================================================

print("\n================================================")
print("EXPORTING WEIGHTS")
print("================================================")


for layer in range(3):

    q_weight = quantized_weights[layer].numpy()

    np.save(
        os.path.join(
            OUTPUT_DIR,
            f"layer{layer}_weights.npy"
        ),
        q_weight
    )

    print(
        f"Layer {layer} weights:",
        q_weight.shape
    )


# ============================================================
# SAVE BIASES
# ============================================================

for layer in range(3):

    q_bias = quantized_biases[layer].numpy()

    np.save(
        os.path.join(
            OUTPUT_DIR,
            f"layer{layer}_bias.npy"
        ),
        q_bias
    )


# ============================================================
# SAVE SCALE / M / SHIFT
# ============================================================

np.save(
    os.path.join(
        OUTPUT_DIR,
        "weight_scales.npy"
    ),
    np.array(weight_scales,
             dtype=np.float64)
)

np.save(
    os.path.join(
        OUTPUT_DIR,
        "activation_scales.npy"
    ),
    np.array(activation_scales,
             dtype=np.float64)
)

np.save(
    os.path.join(
        OUTPUT_DIR,
        "M.npy"
    ),
    np.array(M_values,
             dtype=np.int64)
)

np.save(
    os.path.join(
        OUTPUT_DIR,
        "SHIFT.npy"
    ),
    np.array(shift_values,
             dtype=np.int32)
)


# ============================================================
# HARDWARE WEIGHT PACKING
# ============================================================
#
# IMPORTANT:
#
# Your wrapper reads:
#
#       bram_rd_data[31:0]
#
# and passes:
#
#       array_b = bram_rd_data[31:0]
#
# For a 4x4 array, one 32-bit word therefore contains:
#
#       weight[neuron0]
#       weight[neuron1]
#       weight[neuron2]
#       weight[neuron3]
#
# for ONE input feature.
#
# So a weight matrix:
#
#       [output_neuron][input_feature]
#
# must be transposed before packing.
#
# Each BRAM word:
#
#       byte 0 = neuron 0
#       byte 1 = neuron 1
#       byte 2 = neuron 2
#       byte 3 = neuron 3
#
# ============================================================


def pack_weights_for_hardware(weight_matrix):

    # weight_matrix:
    #
    #       [OUTPUTS][INPUTS]
    #
    outputs, inputs = weight_matrix.shape

    words = []

    # Process output neurons in groups of 4
    for output_base in range(
        0,
        outputs,
        ARRAY_DIM
    ):

        # For every input feature
        for input_idx in range(inputs):

            word = 0

            for lane in range(ARRAY_DIM):

                output_idx = output_base + lane

                if output_idx < outputs:

                    value = int(
                        weight_matrix[
                            output_idx,
                            input_idx
                        ]
                    )

                    # Convert signed INT8 to 8-bit
                    # two's complement representation.
                    value &= 0xFF

                else:

                    # Padding neurons are zero.
                    value = 0

                word |= (
                    value <<
                    (8 * lane)
                )

            words.append(word)

    return np.array(
        words,
        dtype=np.uint32
    )


# ============================================================
# EXPORT HARDWARE WEIGHTS
# ============================================================

for layer in range(3):

    packed = pack_weights_for_hardware(
        quantized_weights[layer].numpy()
    )

    np.save(
        os.path.join(
            OUTPUT_DIR,
            f"layer{layer}_weights_packed.npy"
        ),
        packed
    )

    # Raw binary file for BRAM loading
    packed.tofile(
        os.path.join(
            OUTPUT_DIR,
            f"layer{layer}_weights_packed.bin"
        )
    )

    print(
        f"Layer {layer}: "
        f"{len(packed)} BRAM words"
    )


# ============================================================
# BIAS PACKING
# ============================================================
#
# Your wrapper reads:
#
#       bram_addr = bias_ptr + (bias_idx << 2)
#
# so each bias occupies one 32-bit BRAM word.
#
# ============================================================


for layer in range(3):

    bias = quantized_biases[layer].numpy()

    padded_size = (
        math.ceil(len(bias) / ARRAY_DIM)
        * ARRAY_DIM
    )

    padded = np.zeros(
        padded_size,
        dtype=np.int32
    )

    padded[:len(bias)] = bias

    padded.tofile(
        os.path.join(
            OUTPUT_DIR,
            f"layer{layer}_bias_packed.bin"
        )
    )

    np.save(
        os.path.join(
            OUTPUT_DIR,
            f"layer{layer}_bias_packed.npy"
        ),
        padded
    )


# ============================================================
# EXPORT INPUT IMAGES
# ============================================================
#
# Hardware input format:
#
#       4 images processed together.
#
# Each 32-bit word contains:
#
#       image0 feature
#       image1 feature
#       image2 feature
#       image3 feature
#
# This matches the 4-row array input.
#
# ============================================================


def convert_image_to_hw(image):

    # image is float 0..1

    image = image.numpy()

    image = image.reshape(-1)

    # Convert 0..1 -> 0..127
    image = np.round(
        image * 127.0
    )

    image = np.clip(
        image,
        0,
        127
    )

    return image.astype(np.int8)


# Take first four test images
images = []

labels = []

for i in range(ARRAY_DIM):

    image, label = test_dataset[i]

    images.append(
        convert_image_to_hw(image)
    )

    labels.append(label)


images = np.array(images,
                  dtype=np.int8)


# ------------------------------------------------------------
# Pack four images together
#
# word:
#
#   bits 7:0   = image 0
#   bits 15:8  = image 1
#   bits 23:16 = image 2
#   bits 31:24 = image 3
#
# ------------------------------------------------------------

input_words = []

for feature in range(784):

    word = 0

    for image_idx in range(ARRAY_DIM):

        value = int(
            images[image_idx, feature]
        ) & 0xFF

        word |= (
            value <<
            (8 * image_idx)
        )

    input_words.append(word)


input_words = np.array(
    input_words,
    dtype=np.uint32
)

input_words.tofile(
    os.path.join(
        OUTPUT_DIR,
        "input_4_images.bin"
    )
)

np.save(
    os.path.join(
        OUTPUT_DIR,
        "input_4_images.npy"
    ),
    input_words
)


with open(
    os.path.join(
        OUTPUT_DIR,
        "input_labels.txt"
    ),
    "w"
) as f:

    for label in labels:
        f.write(f"{label}\n")


# ============================================================
# PRINT HARDWARE CONFIGURATION
# ============================================================

print("\n================================================")
print("HARDWARE CONFIGURATION")
print("================================================")

for layer in range(3):

    print(
        f"\nLayer {layer}: "
        f"{LAYER_DIMS[layer]} -> "
        f"{LAYER_DIMS[layer+1]}"
    )

    print(
        "NO_ADD =",
        LAYER_DIMS[layer]
    )

    print(
        "M      =",
        M_values[layer]
    )

    print(
        "SHIFT  =",
        shift_values[layer]
    )


# ============================================================
# FINISHED
# ============================================================

print("\n================================================")
print("DONE")
print("================================================")

print(
    "\nFiles written to:",
    OUTPUT_DIR
)

print(
    "\nNetwork:",
    "784 -> 128 -> 64 -> 10"
)

print(
    "Floating-point accuracy:",
    f"{float_accuracy:.2f}%"
)

print(
    "\nHardware weight files:"
)

for layer in range(3):

    print(
        f"  layer{layer}_weights_packed.bin"
    )

print(
    "\nHardware bias files:"
)

for layer in range(3):

    print(
        f"  layer{layer}_bias_packed.bin"
    )

print(
    "\nQuantization parameters:"
)

print("  M.npy")
print("  SHIFT.npy")
print("  activation_scales.npy")
print("  weight_scales.npy")

print(
    "\nTest input:"
)

print(
    "  input_4_images.bin"
)

print(
    "\nLabels:"
)

print(
    "  input_labels.txt"
)
