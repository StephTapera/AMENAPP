import {AmenDailyWeatherContext} from "./amenDailyTypes";

export function resolveWeatherContext(enabled: boolean, clientWeather?: AmenDailyWeatherContext): AmenDailyWeatherContext | undefined {
  if (!enabled || !clientWeather) return undefined;
  if (clientWeather.alertLevel === "severe") return sanitize(clientWeather);

  const condition = (clientWeather.condition ?? "").toLowerCase();
  const precipitation = clientWeather.precipitationChance ?? 0;
  const temp = clientWeather.temperature;
  const notable =
    condition.includes("rain") ||
    condition.includes("snow") ||
    condition.includes("storm") ||
    condition.includes("fog") ||
    precipitation >= 50 ||
    (typeof temp === "number" && (temp <= 32 || temp >= 95));

  if (!notable) return undefined;
  return sanitize({...clientWeather, alertLevel: clientWeather.alertLevel === "none" ? "notable" : clientWeather.alertLevel});
}

function sanitize(weather: AmenDailyWeatherContext): AmenDailyWeatherContext {
  return {
    temperature: weather.temperature,
    condition: weather.condition,
    high: weather.high,
    low: weather.low,
    precipitationChance: weather.precipitationChance,
    alertLevel: weather.alertLevel,
    summary: weather.summary ?? summaryFor(weather),
    spiritualTieIn: weather.spiritualTieIn,
  };
}

function summaryFor(weather: AmenDailyWeatherContext): string {
  const condition = (weather.condition ?? "").toLowerCase();
  if (weather.alertLevel === "severe") return "Severe weather may affect your day. Plan ahead and stay safe.";
  if (condition.includes("rain")) return "Rain expected today. A good day to slow down where you can.";
  if (condition.includes("snow")) return "Snow may affect travel today. Leave extra margin where possible.";
  if (condition.includes("storm")) return "Storms possible later. Plan ahead and stay safe.";
  if (condition.includes("fog")) return "Fog may make the morning slower. Take extra care as you go.";
  if ((weather.temperature ?? 60) >= 95) return "Extreme heat is possible today. Pace yourself and stay hydrated.";
  if ((weather.temperature ?? 60) <= 32) return "Cold morning ahead. Start slowly where you can.";
  return "Weather may shape the day. Keep a little margin where you can.";
}
