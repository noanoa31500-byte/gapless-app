import json
import math
import random

# --- Helper Functions ---

def generate_organic_poly(center_lat, center_lng, radius_km, variance=0.2, points=16):
    """
    Generates a rough, organic polygon (blob).
    """
    poly = []
    for i in range(points):
        angle = (2 * math.pi * i) / points
        # Vary radius to make it organic
        r = radius_km * (1.0 + random.uniform(-variance, variance))
        
        d_lat = (r / 111.0) * math.sin(angle)
        d_lng = (r / (111.0 * math.cos(math.radians(center_lat)))) * math.cos(angle)
        
        poly.append([
            round(center_lng + d_lng, 5),
            round(center_lat + d_lat, 5)
        ])
    poly.append(poly[0]) # Close loop
    return poly

def generate_river_forests(path_coords, width_km=0.4):
    """
    Generates a series of overlapping blobs along the river to simulate continuous vegetation.
    """
    polygons = []
    for i in range(0, len(path_coords), 1):
        lat, lng = path_coords[i]
        # Left Bank Forest
        polygons.append(generate_organic_poly(lat, lng - 0.004, width_km, variance=0.4))
        # Right Bank Forest
        polygons.append(generate_organic_poly(lat, lng + 0.004, width_km, variance=0.4))
    return polygons

def generate_paddy_fields(center_lat, center_lng, count, size_km):
    """
    Generates scattered large polygons for rice fields.
    """
    polygons = []
    for _ in range(count):
        offset_lat = random.uniform(-0.06, 0.06)
        offset_lng = random.uniform(-0.06, 0.06)
        polygons.append(
            generate_organic_poly(center_lat + offset_lat, center_lng + offset_lng, size_km, variance=0.1, points=8)
        )
    return polygons

def generate_flood_zone(path_coords, max_width_km=1.0):
    """
    Generates a continuous flood zone polygon by buffering a path.
    simplified "ribbon" generation by creating circles along the path and merging them visually.
    Actually, to keep it simple and valid GeoJSON, we'll just generate a dense series of overlapping circles.
    """
    polygons = []
    for lat, lng in path_coords:
        # Generate a "flood blob" at this point
        width = max_width_km * (0.8 + 0.4 * random.random())
        polygons.append(generate_organic_poly(lat, lng, width, variance=0.3, points=10))
    return polygons

# --- Thailand Data Generation ---
# Updated for PCSHS Pathum Thani (14.1109, 100.3977)
# Simulating major canal (Khlong) and river overflow zones
# Big Data: Multiple hazard layers

# 1. Main Chao Phraya River Canal (High resolution path)
th_canal_path = [
    (14.15, 100.40), (14.14, 100.41), (14.13, 100.405),
    (14.12, 100.40), (14.11, 100.39), (14.10, 100.38),
    (14.09, 100.37), (14.08, 100.38), (14.07, 100.39),
    (14.06, 100.395), (14.05, 100.40)
]

# 2. Local Khlongs (Canals) around the school
th_khlong_1_path = [(14.110, 100.390 + i*0.005) for i in range(12)] # East-West Khlong
th_khlong_2_path = [(14.100 + i*0.005, 100.397) for i in range(10)] # North-South Khlong

th_river_polys = generate_river_forests(th_canal_path, width_km=0.6)
th_khlong_polys = generate_flood_zone(th_khlong_1_path, max_width_km=0.3) + \
                  generate_flood_zone(th_khlong_2_path, max_width_km=0.3)

# 3. Aggressive Flood Zones (Rice fields) near school
th_rice_fields = generate_paddy_fields(14.1109, 100.3977, count=40, size_km=1.5)

th_polygons = th_river_polys + th_khlong_polys + th_rice_fields

th_data = {
    "generated_by": "SafeJapan_Unified_Engine",
    "type": "polygon_hazard",
    "region": "th_pathum",
    "total_polygons": len(th_polygons),
    "polygons": th_polygons
}

# --- Japan Data Generation ---

# 1. Osaki City (Eai River Basin - L1/L2 Flood Model)
# Eai river flows roughly West -> Southeast through Furukawa (38.57, 140.95)
jp_eai_river_path = [
    (38.59, 140.90), (38.585, 140.92), (38.58, 140.94),
    (38.575, 140.96), (38.57, 140.98), (38.56, 141.00)
]
# Naruse River (South of Osaki)
jp_naruse_river_path = [
    (38.55, 140.90), (38.545, 140.93), (38.54, 140.96),
    (38.535, 140.99)
]

# Generate main flood zones (River Channel + Overflow)
jp_osaki_zones = []
jp_osaki_zones.extend(generate_flood_zone(jp_eai_river_path, max_width_km=0.8))
jp_osaki_zones.extend(generate_flood_zone(jp_naruse_river_path, max_width_km=0.6))

# Add some "Inland Water" spots (Urban flooding in Furukawa center)
jp_osaki_zones.append(generate_organic_poly(38.575, 140.955, 0.4)) # Station area
jp_osaki_zones.append(generate_organic_poly(38.580, 140.965, 0.3))

# 2. Natori City (Natori River & Coastal Tsunami Zone)
# Natori River mouth (Yuriage)
jp_natori_path = [
    (38.18, 140.88), (38.175, 140.90), (38.17, 140.92), (38.17, 140.94)
]
jp_natori_zones = []
jp_natori_zones.extend(generate_flood_zone(jp_natori_path, max_width_km=0.7))

# Tsunami Inundation Zone (Coastal Strip)
# Simple rectangles/blobs along the coast (Long ~140.95)
for lat in [38.16, 38.17, 38.18, 38.19]:
    jp_natori_zones.append(generate_organic_poly(lat, 140.95, 1.0))

jp_polygons = jp_osaki_zones + jp_natori_zones

jp_data = {
    "generated_by": "SafeJapan_Unified_Engine",
    "data_source": "Municipal_Hazard_Map_Based_Model",
    "targets": ["Osaki_Furukawa", "Natori_Yuriage"],
    "total_polygons": len(jp_polygons),
    "polygons": jp_polygons
}

# Write Files
with open('assets/data/hazard_japan.json', 'w') as f:
    json.dump(jp_data, f, indent=2)

with open('assets/data/hazard_thailand.json', 'w') as f:
    json.dump(th_data, f, indent=2)

print(f"Generated {len(jp_polygons)} polygons for Japan.")
print(f"Generated {len(th_polygons)} polygons for Thailand.")
