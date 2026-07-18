import uvicorn
import logging
from vllm_metal.server import app, create_engine
import vllm_metal.server

# Configure our Native Metal logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("NativeMetalServer")

# Hardcode the model here for the learning environment. 
# We use an OptiQ 4-bit model to fit comfortably in Apple Unified Memory.
MODEL_NAME = "mlx-community/gemma-4-31B-it-OptiQ-4bit"
HOST = "127.0.0.1"
PORT = 8000

def start_server():
    """
    Programmatically starts the vLLM engine using the MLX compute backend.
    This circumvents the CLI, allowing us to build custom pipelines or
    embed the inference engine directly into larger Python applications.
    """
    logger.info(f"Initializing MLX compute backend for {MODEL_NAME}...")
    
    # 1. We manually override the internal engine pointer in the vllm_metal server module
    #    so that the pre-built FastAPI `app` routes can access our instance.
    vllm_metal.server._model_name = MODEL_NAME
    vllm_metal.server._engine = create_engine(MODEL_NAME)
    
    logger.info("vLLM Engine initialized successfully! Memory mapped to Apple Silicon.")
    
    # 2. Start the Uvicorn web server to expose the OpenAI-compatible endpoints
    #    such as /v1/chat/completions
    logger.info(f"Starting API server at http://{HOST}:{PORT}")
    uvicorn.run(
        app,
        host=HOST,
        port=PORT,
        log_level="info"
    )

if __name__ == "__main__":
    start_server()
