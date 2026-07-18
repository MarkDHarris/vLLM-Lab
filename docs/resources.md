## How this list maps to the repo

- **Speed / Metal experiments** → `native_metal/` + MLX links below
- **Kubernetes production shape** → `kubernetes/` + vLLM/K8s links below
- Do not expect Kind CPU throughput to match Metal; use each track for its purpose

## Pro-Tips for Production LLM Engineering

If you are just getting started building real-world applications on top of this local lab, here are a few advanced concepts you'll want to master:

1. **Watch Your Context Window:** The `max_tokens` you ask the model to generate is only part of the puzzle. Sending a 32,000-token prompt will consume a massive chunk of VRAM *during the pre-fill phase*. On unified memory architectures, if you blow past your memory limits during pre-fill, macOS will aggressively swap memory to your SSD, turning generations into a crawl (1 token every 5 seconds). 
2. **PagedAttention is Key:** The reason `vLLM` is the industry standard (and why `vllm-metal` is so powerful) is because of **PagedAttention**. Instead of statically allocating huge chunks of memory for the KV-cache of every request, vLLM pages it just like an operating system does with RAM. This allows you to serve 4x to 10x more concurrent users on the same hardware.
3. **Understand Quantization:** You are currently running **4-bit quantized** models. This is roughly 1/4th the memory footprint of a standard 16-bit (FP16) model. While you lose a tiny bit of precision in the model's "reasoning," 4-bit usually strikes the perfect balance for local testing. Look into the differences between **AWQ**, **GPTQ**, and Apple's **OptiQ**.
4. **Always Specify Max Tokens:** As you learned, vLLM (by default) might cap generations at 16 tokens to prevent infinite loops from draining server resources. Always explicitly specify your `max_tokens` (or `max_completion_tokens`) in your API payload.
5. **Prompt Formatting Matters:** Llama 3, Gemma, and Mistral all use completely different internal "chat templates" (e.g., `<|start_header_id|>` vs `<start_of_turn>`). If you don't use their expected format, the model will output garbage. Fortunately, by using the `/v1/chat/completions` endpoint, vLLM automatically applies the correct Jinja template for the loaded model on your behalf!

---

## The Ultimate LLM Engineering Resource List

To transition from running local scripts to designing planet-scale AI architectures, you need to understand the fundamentals of Transformers, memory management, and MLOps. Here are several dozen resources to accelerate your journey.

### 📚 Essential Books
1. **[Build a Large Language Model (From Scratch)](https://www.manning.com/books/build-a-large-language-model-from-scratch)** by Sebastian Raschka - The absolute best hands-on guide to coding a GPT from the ground up in PyTorch.
2. **[Designing Machine Learning Systems](https://www.oreilly.com/library/view/designing-machine-learning/9781098107956/)** by Chip Huyen - Crucial for understanding how to deploy, monitor, and scale models in Kubernetes and production environments.
3. **[Natural Language Processing with Transformers](https://www.oreilly.com/library/view/natural-language-processing/9781098136789/)** by Lewis Tunstall, et al. - A fantastic deep dive into the Hugging Face ecosystem.
4. **[Deep Learning](https://www.deeplearningbook.org/)** by Ian Goodfellow, Yoshua Bengio, and Aaron Courville - The mathematical foundation of modern neural networks.

### 🎓 Video Courses & Lectures
5. **[Neural Networks: Zero to Hero](https://karpathy.ai/zero-to-hero.html)** by Andrej Karpathy - A masterful, highly accessible YouTube series building neural networks from scratch.
6. **[fast.ai: Practical Deep Learning for Coders](https://course.fast.ai/)** by Jeremy Howard - A legendary top-down approach to getting ML models working immediately.
7. **[DeepLearning.AI: Generative AI with Large Language Models](https://www.coursera.org/learn/generative-ai-with-llms)** - AWS and Coursera's joint course on the lifecycle of generative models.
8. **[Stanford CS25: Transformers United](https://web.stanford.edu/class/cs25/)** - Seminars from the creators of the Transformer architecture.
9. **[Hugging Face NLP Course](https://huggingface.co/learn/nlp-course/chapter1/1)** - Free, interactive course on fine-tuning and deploying open-source models.

### 📄 Seminal Papers (Must Reads)
10. **[Attention Is All You Need (2017)](https://arxiv.org/abs/1706.03762)** - The original Google paper that introduced the Transformer.
11. **[PagedAttention / vLLM Paper (2023)](https://arxiv.org/abs/2309.06180)** - Explains exactly how the vLLM engine you are running manages memory to achieve 24x throughput.
12. **[FlashAttention-2 (2023)](https://arxiv.org/abs/2307.08691)** - How modern attention algorithms avoid memory bottlenecks on GPUs.
13. **[LoRA: Low-Rank Adaptation (2021)](https://arxiv.org/abs/2106.09685)** - The foundation of how we fine-tune massive models cheaply.
14. **[AWQ: Activation-aware Weight Quantization (2023)](https://arxiv.org/abs/2306.00978)** - Crucial reading to understand how your 4-bit models maintain accuracy.

### 🧠 Apple Silicon & MLX Specifics
15. **[Apple MLX Framework GitHub](https://github.com/ml-explore/mlx)** - The core C++/Python framework powering this entire repository.
16. **[MLX Examples Repository](https://github.com/ml-explore/mlx-examples)** - Learn how to run Whisper, Stable Diffusion, and LLMs natively on Macs.
17. **[Understanding Apple's Unified Memory Architecture](https://www.apple.com/mac/)** - Why Macs have a unique advantage for local LLM inference over traditional PC architectures.
18. **[Hugging Face `mlx-community`](https://huggingface.co/mlx-community)** - The hub for pre-quantized, ready-to-run models for Apple Silicon.

### ⚙️ Production Deployment & Tooling
19. **[Official vLLM Documentation](https://docs.vllm.ai/en/latest/)** - Read about Tensor Parallelism, Pipeline Parallelism, and engine kwargs.
20. **[OpenAI API Specification](https://platform.openai.com/docs/api-reference)** - vLLM perfectly mimics this spec. Knowing it inside and out is mandatory.
21. **[Docker & Kubernetes Networking](https://kubernetes.io/docs/concepts/services-networking/)** - To move this MacBook cluster to the cloud, you need to master k8s ingress.
22. **[Baseten / Truss Documentation](https://baseten.co/docs)** - Great architectural reading on how cloud providers package and scale custom models.
23. **[Modal Serverless GPUs](https://modal.com/)** - If you outgrow your MacBook, this is how you deploy vLLM to the cloud in seconds.
24. **[LangChain](https://python.langchain.com/) / [LlamaIndex](https://www.llamaindex.ai/)** - Frameworks for building RAG applications on top of your local vLLM cluster.

### 🌐 Blogs, Articles, and Communities
25. **[r/LocalLLaMA](https://www.reddit.com/r/LocalLLaMA/)** - The definitive Reddit community for running LLMs on local hardware.
26. **[The Hugging Face Blog](https://huggingface.co/blog)** - Constant updates on open-source model releases (like Llama 3 and Gemma 2).
27. **[Lilian Weng's Blog (OpenAI)](https://lilianweng.github.io/)** - Some of the most deeply researched technical summaries of LLM capabilities.
28. **[Simon Willison's Weblog](https://simonwillison.net/)** - Exceptional daily commentary on practical AI engineering and prompt injection.
29. **[Sebastian Raschka's "Ahead of AI"](https://magazine.sebastianraschka.com/)** - Phenomenal weekly deep dives into new architectures and research papers.
30. **[Latent Space Podcast](https://www.latent.space/)** - High-level interviews with the engineers building the tools you use every day.
