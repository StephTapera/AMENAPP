const express = require('express');
const { GoogleGenerativeAI } = require('@google/generative-ai');

const app = express();
app.use(express.json());

const genAI = new GoogleGenerativeAI(process.env.GOOGLE_AI_API_KEY);
const model = genAI.getGenerativeModel({
  model: 'models/gemini-2.5-flash',
  generationConfig: {
    temperature: 0.7,
    maxOutputTokens: 2048,
  }
});

// Health check
app.get('/', (req, res) => {
  res.json({ status: 'healthy', service: 'AMEN AI Server', version: '1.0.0' });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Generate Fun Bible Fact
app.post('/generateFunBibleFact', async (req, res) => {
  try {
    const category = req.body.data?.category || 'random';
    const prompt = `Share a fascinating Bible fact about ${category}. Keep it 2-3 sentences, educational and engaging.`;
    
    const result = await model.generateContent(prompt);
    const fact = result.response.text();
    
    res.json({ result: { fact } });
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Bible Chat
app.post('/bibleChat', async (req, res) => {
  try {
    const { message, history } = req.body;
    const prompt = `You are a knowledgeable Bible study assistant. Provide thoughtful, biblically-grounded responses.

User's question: ${message}

Provide a helpful, accurate response based on biblical teachings.`;
    
    const result = await model.generateContent(prompt);
    const response = result.response.text();
    
    res.json({ response });
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: error.message });
  }
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 AMEN AI Server listening on port ${PORT}`);
  console.log('✅ Endpoints: /bibleChat, /generateFunBibleFact');
});
