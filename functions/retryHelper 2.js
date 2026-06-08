// retryHelper.js — exponential backoff with jitter for external API calls

async function withRetry(fn, maxAttempts = 3, baseDelayMs = 500) {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (attempt === maxAttempts) throw err;
      const jitter = Math.random() * 200;
      const delay = baseDelayMs * Math.pow(2, attempt - 1) + jitter;
      await new Promise(r => setTimeout(r, delay));
    }
  }
}

module.exports = { withRetry };
