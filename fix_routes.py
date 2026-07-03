import re

def fix_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    active_pattern = re.compile(r'(@router\.get\("/orders/active"\)\nasync def get_active_.*?_order\(.*?\n    \}.*?\n)', re.DOTALL)
    
    match = active_pattern.search(content)
    if not match:
        print(f"Could not find active route in {filepath}")
        return
        
    active_route = match.group(1)
    # Remove it from the original place
    content = content.replace(active_route, "")
    
    # Find where to insert
    insert_pattern = r'(@router\.get\("/orders/\{order_id\}"\)\nasync def)'
    insert_match = re.search(insert_pattern, content)
    if not insert_match:
        print(f"Could not find insert point in {filepath}")
        return
        
    # Insert it
    content = content.replace(insert_match.group(1), active_route + "\n\n" + insert_match.group(1))
    
    with open(filepath, 'w') as f:
        f.write(content)
    print(f"Fixed {filepath}")

fix_file('/var/www/ziggo/ziggo_backend/app/api/v1/food.py')
fix_file('/var/www/ziggo/ziggo_backend/app/api/v1/market.py')
