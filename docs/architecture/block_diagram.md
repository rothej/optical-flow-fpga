# Optical Flow Accelerator Architecture

All block diagrams created using [Mermaid](https://mermaid.ai/open-source/syntax/block.html) in markdown.

## Top-Level Block Diagram

```mermaid
%%{init: {'theme':'base', 'themeVariables': {
  'primaryColor':'#e8f4f8',
  'primaryTextColor':'#1a1a1a',
  'primaryBorderColor':'#4a90e2',
  'lineColor':'#666',
  'secondaryColor':'#fff9e6',
  'tertiaryColor':'#f0f0f0',
  'background':'#ffffff'
}}}%%
graph TB
    subgraph inputs["Input Streams"]
        curr[Current Frame<br/>8-bit pixels]
        prev[Previous Frame<br/>8-bit pixels]
        valid[pixel_valid]
    end

    subgraph gradient["Gradient Computation Module"]
        lb_curr[Line Buffer 5x5<br/>Current Frame]
        lb_prev[Line Buffer 5x5<br/>Previous Frame]
        sobel[Sobel Operators<br/>Ix, Iy computation]
        temporal[Temporal Difference<br/>It calculation]

        curr --> lb_curr
        prev --> lb_prev
        lb_curr --> sobel
        lb_prev --> sobel
        lb_curr --> temporal
        lb_prev --> temporal
    end

    subgraph solver["Lucas-Kanade Solver Module"]
        accum[Gradient Accumulation<br/>Sum Ix^2, Iy^2, IxIy, IxIt, IyIt]
        matrix[Matrix Operations<br/>2x2 inversion]
        flow_calc[Flow Calculation<br/>Solve for u, v]

        sobel --> accum
        temporal --> accum
        accum --> matrix
        matrix --> flow_calc
    end

    subgraph outputs["Outputs"]
        u[u flow<br/>16-bit signed]
        v[v flow<br/>16-bit signed]
        flow_valid[flow_valid]
    end

    flow_calc --> u
    flow_calc --> v
    flow_calc --> flow_valid

    style gradient fill:#e8f4f8
    style solver fill:#fff9e6
    style inputs fill:#f0f0f0
    style outputs fill:#f0f0f0
```

---

## Module Heirarchy

```mermaid
%%{init: {'theme':'base', 'themeVariables': {
  'primaryColor':'#e8f4f8',
  'primaryTextColor':'#1a1a1a',
  'primaryBorderColor':'#4a90e2',
  'lineColor':'#666',
  'secondaryColor':'#fff9e6',
  'background':'#ffffff'
}}}%%
graph TD
    top[optical_flow_top]

    grad[gradient_compute]
    lb1[line_buffer_5x5<br/>current frame]
    lb2[line_buffer_5x5<br/>previous frame]

    solver[lucas_kanade_solver]
    accum_mod[gradient_accumulator]

    top --> grad
    top --> solver
    grad --> lb1
    grad --> lb2
    solver --> accum_mod

    style top fill:#4a90e2,color:#fff
    style grad fill:#e8f4f8
    style solver fill:#fff9e6
```

---

### Data Flow

The accelerator processes frames in a streaming fashion.

#### Line Buffering (5 cycles latency)
- Builds 5x5 windows for spatial operations
- Maintains separate buffers for current/previous frame

#### Gradient Computation (1 cycle - combinational)
- Sobel X/Y operators on averaged frame: $I_{avg} = \frac{I_{curr} + I_{prev}}{2}$
- Spatial gradients: $I_x$, $I_y$ via convolution
- Temporal gradient: $I_t = I_{prev} - I_{curr}$ on center pixels
- Combinational Sobel accumulation (critical path)

#### Flow Solver (1 cycle - combinational)
- Accumulates gradients over 5x5 window:
$$
A = \begin{bmatrix}
\sum I_x^2 & \sum I_x I_y \\
\sum I_x I_y & \sum I_y^2
\end{bmatrix}, \quad
b = -\begin{bmatrix}
\sum I_x I_t \\
\sum I_y I_t
\end{bmatrix}
$$
- Matrix inversion: Computes $\det(A)$, checks solvability
- Flow solution: $\mathbf{u} = [u, v]^T = A^{-1} \mathbf{b}$ via Cramer's rule
- Matrix multiplication and division (critical path)

---

# Critical Timing Paths (Unoptimized)

```mermaid
%%{init: {'theme':'base', 'themeVariables': {
  'primaryColor':'#e8f4f8',
  'primaryTextColor':'#1a1a1a',
  'primaryBorderColor':'#4a90e2',
  'lineColor':'#666',
  'background':'#ffffff'
}}}%%
graph LR
    subgraph "Longest Path: ~120ns"
        A[Line Buffer<br/>Output] -->|8-bit| B[Sobel<br/>Accumulation]
        B -->|12-bit| C[Matrix<br/>Multiply]
        C -->|24-bit| D[Division]
        D -->|16-bit| E[Output<br/>Register]
    end

    style A fill:#90EE90
    style B fill:#FFB6C1
    style C fill:#FFB6C1
    style D fill:#FFB6C1
    style E fill:#90EE90
```
