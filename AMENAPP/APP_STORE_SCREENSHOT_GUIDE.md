# App Store Screenshot Guide

## Sample Data Generator

Use this tool to populate your app with realistic sample posts for App Store screenshots.

### How to Use

1. **Open Developer Menu**
   - Go to Settings → (scroll to bottom) → Developer Menu
   - Or add a debug shortcut in your app

2. **Generate Sample Posts**
   - Tap "Sample Posts Generator"
   - Tap "Generate Sample Posts"
   - Wait for confirmation (15 posts total)

3. **What Gets Generated**
   - **5 OpenTable Posts**: Discussion questions about faith, life, and spiritual growth
   - **5 Prayer Requests**: Heartfelt prayer requests covering various life situations
   - **5 Testimonies**: Powerful testimony stories of God's faithfulness

### Taking Screenshots

After generating posts, navigate to each section:

#### OpenTable Screenshots
- Go to Feed → Filter by OpenTable
- Capture engaging discussion threads
- Show variety of topics (peace, forgiveness, purpose, prayer, hope)

#### Prayer View Screenshots
- Go to Feed → Filter by Prayer
- Capture prayer requests
- Show community support (amen counts, comments)
- Highlight different types (health, work, family, breakthrough)

#### Testimonies Screenshots
- Go to Feed → Filter by Testimonies
- Capture powerful testimony stories
- Show transformation narratives
- Highlight God's faithfulness themes

### Post Details

Each sample post includes:
- Realistic, relatable content
- Random engagement metrics (5-25 amens, 3-20 lightbulbs, 0-8 comments)
- Staggered timestamps (1 hour apart)
- Your user account as the author

### After Screenshots

**Clear Sample Data**:
- Return to Sample Posts Generator
- Tap "Clear Sample Posts"
- Removes all posts created by your account
- Use this to clean up after screenshot session

### Sample Post Examples

**OpenTable**:
- "How do you find peace when everything feels chaotic?"
- "What does it mean to truly forgive someone who hurt you deeply?"
- "Can we talk about finding purpose in our daily work?"

**Prayer**:
- "Please pray for my mom who's going in for surgery tomorrow..."
- "Asking for prayers as I start my new job on Monday..."
- "My marriage is going through a difficult season..."

**Testimonies**:
- "God brought me out of the darkest depression..."
- "I was drowning in debt and had no way out..."
- "My doctor said I'd never have children. Today I'm holding my miracle baby..."

### Tips for Great Screenshots

1. **Variety**: Use different categories to show app versatility
2. **Engagement**: Posts include realistic interaction counts
3. **Timing**: Posts are spaced 1 hour apart for natural feel
4. **Clean UI**: Black and white design looks professional in screenshots
5. **Context**: Show full post cards with rounded edges and clean design

### Troubleshooting

**Posts not appearing?**
- Check that you're signed in
- Refresh the feed (pull down)
- Verify Firestore permissions
- Check console logs for errors

**Need different content?**
- Edit `SampleDataGenerator.swift`
- Modify `openTablePosts`, `prayerPosts`, or `testimonyPosts` arrays
- Rebuild and regenerate

### Production Note

⚠️ **Remove Developer Menu before App Store submission**
- This tool is for development only
- Sample posts are tied to your test account
- Clear all sample data before production release

## Screenshot Checklist

- [ ] Generate sample posts
- [ ] Take OpenTable screenshots (2-3 images)
- [ ] Take Prayer screenshots (2-3 images)
- [ ] Take Testimonies screenshots (2-3 images)
- [ ] Capture profile view with posts
- [ ] Show interaction buttons (amen, lightbulb, comments)
- [ ] Highlight clean black & white design
- [ ] Clear sample posts when done
- [ ] Test that real posts still work correctly

## App Store Image Requirements

- **iPhone**: 6.7" display (1290 x 2796 pixels)
- **iPad**: 12.9" display (2048 x 2732 pixels)
- **Format**: PNG or JPEG
- **Color Space**: sRGB or Display P3
- **Max File Size**: 500 MB per screenshot

## Need More Help?

Check `SampleDataGenerator.swift` for:
- Full list of sample posts
- Customization options
- Database structure
- Error handling

Happy screenshot taking! 📸✨
