// genius-lyrics.js
import pkg from 'genius-lyrics-api';
const { getSong } = pkg;  // fetchSong değil, pkg içinden alıyoruz

// kendi async wrapper fonksiyonumuz
export async function fetchSong(apiKey, title, artist) {
    const options = { apiKey, title, artist, optimizeQuery: true };
    try {
        const song = await getSong(options);
        if (!song) return null;
        return {
            id: song.id,
            title: song.title,
            url: song.url,
            albumArt: song.albumArt,
            lyrics: song.lyrics
        };
    } catch (err) {
        console.error("Song fetch error:", err);
        return null;
    }
}

// CLI çalıştırma kısmı
const [,, apiKey, songTitle, artistName] = process.argv;

if (apiKey && songTitle && artistName) {
    (async () => {
        const song = await fetchSong(apiKey, songTitle, artistName);
        if (!song) {
            console.log("Song not found.");
            return;
        }
        console.log(song.lyrics);
    })();
}