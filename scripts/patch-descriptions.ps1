$baseUrl = "https://qspilpbvcldgelgwwrdr.supabase.co/rest/v1/catalog_nodes"
$key     = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFzcGlscGJ2Y2xkZ2VsZ3d3cmRyIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MDg4Mjk2NiwiZXhwIjoyMDk2NDU4OTY2fQ.UveKRbIFF28Wg7Gs7PcsMAMVojEqFI2BwfGlH1XRiR4"

$headers = @{
    "apikey"        = $key
    "Authorization" = "Bearer $key"
    "Content-Type"  = "application/json"
    "Prefer"        = "return=minimal"
}

$updates = @(
    @{ n = "Home Cleaning Services";          d = "Professional home cleaning for apartments, villas, and individual rooms. Choose from basic or deep cleaning packages tailored to your space." }
    @{ n = "Basic Full Home Cleaning";        d = "Regular cleaning packages covering all rooms to keep your home tidy and fresh. Ideal for weekly or fortnightly maintenance." }
    @{ n = "Deep Full Home Cleaning";         d = "Thorough deep cleaning of every room and surface in your home. Targets hidden grime, dust, and bacteria for a truly spotless result." }
    @{ n = "Furnished Apartment";             d = "Cleaning packages for furnished apartments of all BHK sizes, covering furniture, fixtures, and all surfaces." }
    @{ n = "Un-Furnished Apartment";          d = "Cleaning packages for empty apartments, ideal for move-in preparation or post-renovation cleanup." }
    @{ n = "Unfurnished Apartment";           d = "Cleaning packages for vacant apartments, perfect for move-in readiness and post-construction cleanup." }
    @{ n = "Furnished villa";                 d = "Comprehensive cleaning packages for furnished villas, from basic upkeep to full deep cleaning." }
    @{ n = "Furnished Villa";                 d = "Comprehensive cleaning packages for furnished villas, from basic upkeep to full deep cleaning." }
    @{ n = "Unfurnished villa";               d = "Cleaning packages for empty villas, ideal for move-in, post-renovation, or handover preparation." }
    @{ n = "Un-Furnished Villa";              d = "Cleaning packages for empty villas, ideal for move-in, post-renovation, or handover preparation." }
    @{ n = "Bathrrom cleaning";               d = "Professional bathroom cleaning services ranging from basic sanitization to deep lime scale removal." }
    @{ n = "Basic Bathroom Cleaning";         d = "Standard bathroom cleaning including toilet scrubbing, sink sanitization, and floor mopping." }
    @{ n = "Deep Bathroom Cleaning";          d = "Intensive bathroom cleaning with lime scale removal, grout scrubbing, and full surface sanitization." }
    @{ n = "Kitchen cleaning";                d = "Professional kitchen cleaning covering stovetops, chimneys, sinks, and appliances." }
    @{ n = "Furniture cleaning";              d = "Professional cleaning for sofas, carpets, mattresses, and dining sets to restore freshness and hygiene." }
    @{ n = "Sofa cleaning";                   d = "Deep cleaning and stain removal for all sofa types and sizes." }
    @{ n = "Carpet cleaning";                 d = "Professional carpet cleaning to lift embedded dirt, stains, and odors." }
    @{ n = "Mattress Cleaning";               d = "Sanitizing and deep cleaning for mattresses to eliminate dust mites and allergens." }
    @{ n = "Dining Table Cleaning";           d = "Professional cleaning of dining tables and chairs for a fresh, hygienic eating surface." }
    @{ n = "Ac Services";                     d = "Professional air conditioner inspection, repair, and servicing to keep your AC running efficiently." }
    @{ n = "Ac Repair";                       d = "Expert diagnosis and repair for common AC problems including gas leaks, water leakage, and power issues." }
    @{ n = "Appliance Services";              d = "Professional repair and maintenance for household appliances including refrigerators, washing machines, and water purifiers." }
    @{ n = "EV Services";                     d = "Comprehensive electric vehicle maintenance, repair, and diagnostic services by certified technicians." }
    @{ n = "Overhead Tank";                   d = "Professional cleaning and sanitization services for overhead water storage tanks of all capacities." }
    @{ n = "Underground Tank";                d = "Thorough cleaning and disinfection services for underground water storage tanks." }
    @{ n = "Water tank cleaning";             d = "Professional cleaning and sanitization for overhead and underground water storage tanks." }
    @{ n = "Other";                           d = "Additional home maintenance and specialized cleaning services to meet your unique needs." }
    @{ n = "1 BHK Furnished Basic cleaning";              d = "Light sweeping, mopping, dusting, and surface cleaning for a 1 BHK furnished home. Perfect for regular weekly upkeep." }
    @{ n = "1 BHK Furnished Full Home Deep Cleaning";     d = "Complete deep cleaning of all rooms, surfaces, fans, and fixtures in your 1 BHK furnished home, including kitchen and bathroom." }
    @{ n = "1 BHK Un-Furnished Basic Cleaning";           d = "Basic sweep, mop, and dusting for an empty 1 BHK apartment. Ideal for move-in preparation or post-renovation cleanup." }
    @{ n = "1 BHK Un-Furnished Full Home Deep Cleaning";  d = "Thorough deep cleaning of all surfaces, floors, and hard-to-reach areas in an unfurnished 1 BHK unit." }
    @{ n = "2 BHK Furnished Basic Cleaning";              d = "Light sweeping, mopping, dusting, and surface cleaning for a 2 BHK furnished home. Perfect for regular weekly upkeep." }
    @{ n = "2 BHK Furnished Full Home Deep Cleaning";     d = "Complete deep cleaning of all rooms, surfaces, fans, and fixtures in your 2 BHK furnished home, including kitchen and bathroom." }
    @{ n = "2 BHK Un-Furnished Basic Cleaning";           d = "Basic sweep, mop, and dusting for an empty 2 BHK apartment. Ideal for move-in preparation or post-renovation cleanup." }
    @{ n = "2 BHK Un-Furnished Full Home Deep Cleaning";  d = "Thorough deep cleaning of all surfaces, floors, and hard-to-reach areas in an unfurnished 2 BHK unit." }
    @{ n = "2  BHK Un-Furnished Full Home Deep Cleaning"; d = "Thorough deep cleaning of all surfaces, floors, and hard-to-reach areas in an unfurnished 2 BHK unit." }
    @{ n = "3 BHK Furnished Basic Cleaning";              d = "Light sweeping, mopping, dusting, and surface cleaning for a 3 BHK furnished home. Perfect for regular weekly upkeep." }
    @{ n = "3 BHK Furnished Full Home Deep Cleaning";     d = "Complete deep cleaning of all rooms, surfaces, fans, and fixtures in your 3 BHK furnished home, including kitchen and bathroom." }
    @{ n = "3 BHK Un-Furnished Basic Cleaning";           d = "Basic sweep, mop, and dusting for an empty 3 BHK apartment. Ideal for move-in preparation or post-renovation cleanup." }
    @{ n = "3 BHK Un-Furnished Full Home Deep Cleaning";  d = "Thorough deep cleaning of all surfaces, floors, and hard-to-reach areas in an unfurnished 3 BHK unit." }
    @{ n = "4 BHK Furnished Basic Cleaning";              d = "Light sweeping, mopping, dusting, and surface cleaning for a 4 BHK furnished home. Perfect for regular weekly upkeep." }
    @{ n = "4 BHK Furnished Full Home Deep Cleaning";     d = "Complete deep cleaning of all rooms, surfaces, fans, and fixtures in your 4 BHK furnished home, including kitchen and bathroom." }
    @{ n = "4 BHK Un-Furnished Basic Cleaning";           d = "Basic sweep, mop, and dusting for an empty 4 BHK apartment. Ideal for move-in preparation or post-renovation cleanup." }
    @{ n = "4 BHK Un-Furnished Full Home Deep Cleaning";  d = "Thorough deep cleaning of all surfaces, floors, and hard-to-reach areas in an unfurnished 4 BHK unit." }
    @{ n = "5 BHK Furnished Basic Cleaning";              d = "Light sweeping, mopping, dusting, and surface cleaning for a 5 BHK furnished home. Perfect for regular weekly upkeep." }
    @{ n = "5 BHK Furnished Full Home Deep Cleaning";     d = "Complete deep cleaning of all rooms, surfaces, fans, and fixtures in your 5 BHK furnished home, including kitchen and bathroom." }
    @{ n = "5 BHK Un-Furnished Basic Cleaning";           d = "Basic sweep, mop, and dusting for an empty 5 BHK apartment. Ideal for move-in preparation or post-renovation cleanup." }
    @{ n = "5 BHK Un-Furnished Full Home Deep Cleaning";  d = "Thorough deep cleaning of all surfaces, floors, and hard-to-reach areas in an unfurnished 5 BHK unit." }
    @{ n = "Basic Bathroom Cleaning with Glass Barrier and Seperation-1";         d = "Standard cleaning of 1 bathroom including toilet scrubbing, sink sanitization, floor mopping, and glass barrier cleaning." }
    @{ n = "Basic Bathroom Cleaning with Glass Barrier and Seperation-2 pack";    d = "Standard cleaning of 2 bathrooms including toilet scrubbing, floor mopping, and glass barrier sanitization." }
    @{ n = "Basic Bathroom Cleaning with Glass Barrier and Seperation-3 pack";    d = "Standard cleaning of 3 bathrooms including toilet scrubbing, floor mopping, and glass barrier sanitization." }
    @{ n = "Basic Bathroom Cleaning-1";                                           d = "Professional basic cleaning of 1 bathroom including toilet scrubbing, sink cleaning, and floor mopping." }
    @{ n = "Basic Bathroom Cleaning-2 pack";                                      d = "Professional basic cleaning of 2 bathrooms including toilet scrubbing, sink cleaning, and floor mopping." }
    @{ n = "Basic Bathroom Cleaning-3 pack";                                      d = "Professional basic cleaning of 3 bathrooms including toilet scrubbing, sink cleaning, and floor mopping." }
    @{ n = "Basic Bathroom Cleaning-Extra Large -1";                              d = "Basic cleaning for 1 extra-large bathroom with extended surface scrubbing, toilet sanitization, and floor mopping." }
    @{ n = "Basic Bathroom Cleaning-Extra Large -2 pack";                         d = "Basic cleaning of 2 extra-large bathrooms with extended surface scrubbing and full sanitization." }
    @{ n = "Basic Bathroom Cleaning-Extra Large -3 pack";                         d = "Basic cleaning of 3 extra-large bathrooms with extended surface scrubbing and full sanitization." }
    @{ n = "Deep Bathroom Cleaning Extra Large- 1 pack";                          d = "Intensive deep cleaning of 1 extra-large bathroom, covering lime scale removal, grout scrubbing, and full disinfection." }
    @{ n = "Deep Bathroom Cleaning Extra Large- 2 pack";                          d = "Intensive deep cleaning of 2 extra-large bathrooms, covering lime scale removal, grout scrubbing, and full disinfection." }
    @{ n = "Deep Bathroom Cleaning with Glass Barrier and Seperation- 1 pack";    d = "Intensive deep cleaning of 1 bathroom with glass barrier, including lime scale removal and full surface sanitization." }
    @{ n = "Deep Bathroom Cleaning with Glass Barrier and Seperation- 2 pack";    d = "Intensive deep cleaning of 2 bathrooms with glass barriers, including lime scale removal and full surface sanitization." }
    @{ n = "Deep Bathroom Cleaning with Glass Barrier and Seperation- 3 pack";    d = "Intensive deep cleaning of 3 bathrooms with glass barriers, including lime scale removal and full surface sanitization." }
    @{ n = "Deep Bathroom Cleaning- 1 pack";                                      d = "Intensive deep cleaning of 1 bathroom including lime scale removal, grout scrubbing, and complete disinfection." }
    @{ n = "Deep Bathroom Cleaning- 2 pack";                                      d = "Intensive deep cleaning of 2 bathrooms including lime scale removal, grout scrubbing, and complete disinfection." }
    @{ n = "Deep Bathroom Cleaning- 3 pack";                                      d = "Intensive deep cleaning of 3 bathrooms including lime scale removal, grout scrubbing, and complete disinfection." }
    @{ n = "Deep Bathroom Cleaning- Lime Scaling";                                d = "Specialized treatment to remove stubborn lime scale buildup from tiles, fittings, and bathroom surfaces." }
    @{ n = "Gas Stove Cleaning";                              d = "Deep cleaning of gas burners, grates, drip pans, and stove surface to remove grease and food residue." }
    @{ n = "Chimney Cleaning";                                d = "Professional cleaning of kitchen chimney filters, mesh, and interior to restore airflow and eliminate grease buildup." }
    @{ n = "Kitchen Sink Cleaning";                           d = "Thorough scrubbing and descaling of the kitchen sink, drain, and surrounding countertop." }
    @{ n = "Shelves and Trolley Cleaning";                    d = "Cleaning of kitchen shelves, trolleys, and storage racks to remove grease, dust, and accumulated grime." }
    @{ n = "Microwave Cleaning";                              d = "Interior and exterior cleaning of your microwave oven to remove food splatters, stains, and odors." }
    @{ n = "Complete Kitchen Cleaning(Full Kitchen)";         d = "Comprehensive cleaning of your entire kitchen including stovetop, chimney, sink, appliances, and all countertops." }
    @{ n = "Complete Kitchen Cleaning(Appliances & Chimney)"; d = "Deep cleaning of all kitchen appliances and chimney for a spotless, grease-free kitchen." }
    @{ n = "Complete Kitchen Cleaning(with Appliances)";      d = "Full kitchen clean including countertops, stovetop, and all major kitchen appliances." }
    @{ n = "Complete Kitchen Cleaning(with Chimney)";         d = "Full kitchen cleaning with dedicated chimney servicing for a spotless, odor-free cooking space." }
    @{ n = "Move-In Kitchen Cleaning(Empty Kitchen)";         d = "Detailed cleaning of an empty kitchen to prepare it for move-in, covering all surfaces, cabinets, and fixtures." }
    @{ n = "Move-In Kitchen Cleaning(with Appliances)";       d = "Move-in ready kitchen cleaning including installed appliances, countertops, and all surfaces." }
    @{ n = "Move-In Kitchen Cleaning(with Chimney)";          d = "Move-in kitchen cleaning with chimney servicing for a fresh, ready-to-use cooking space." }
    @{ n = "Empty Kitchen Cleaning(Appliances & Chimney)";    d = "Thorough cleaning of an empty kitchen with full appliance and chimney servicing." }
    @{ n = "Double Door Fridge Cleaning";                     d = "Interior and exterior cleaning of a double-door refrigerator including shelves, drawers, and door seals." }
    @{ n = "2 Cupboards Wet Wiping(Except Kitchen)";          d = "Wet wiping of 2 cupboards outside the kitchen, covering shelves, doors, and handles." }
    @{ n = "Sofa Cleaning- 3 Seats";  d = "Professional deep cleaning of a 3-seater sofa to remove dust, stains, and allergens." }
    @{ n = "Sofa Cleaning- 4 Seats";  d = "Professional deep cleaning of a 4-seater sofa to remove dust, stains, and allergens." }
    @{ n = "Sofa Cleaning- 5 Seats";  d = "Professional deep cleaning of a 5-seater sofa to remove dust, stains, and allergens." }
    @{ n = "Sofa Cleaning- 6 Seats";  d = "Professional deep cleaning of a 6-seater sofa to remove dust, stains, and allergens." }
    @{ n = "Sofa Cleaning- 7 Seats";  d = "Professional deep cleaning of a 7-seater sofa to remove dust, stains, and allergens." }
    @{ n = "Sofa Cleaning- 8 Seats";  d = "Professional deep cleaning of an 8-seater sofa to remove dust, stains, and allergens." }
    @{ n = "Sofa Cleaning- 10 Seats"; d = "Professional deep cleaning of a 10-seater sofa to remove dust, stains, and allergens." }
    @{ n = "Sofa Cleaning- 11 Seats"; d = "Professional deep cleaning of an 11-seater sofa to remove dust, stains, and allergens." }
    @{ n = "Sofa Cleaning- 12 Seats"; d = "Professional deep cleaning of a 12-seater sofa to remove dust, stains, and allergens." }
    @{ n = "Carpet Cleaning Extra Large(25-50sq.ft)";   d = "Professional deep cleaning of carpets between 25-50 sq.ft to remove embedded dirt, stains, and odors." }
    @{ n = "Carpet Cleaning Extra Large(50-100sq.ft)";  d = "Professional deep cleaning of carpets between 50-100 sq.ft to remove embedded dirt, stains, and odors." }
    @{ n = "Carpet Cleaning Extra Large(150-200sq.ft)"; d = "Professional deep cleaning of large carpets between 150-200 sq.ft to remove embedded dirt, stains, and odors." }
    @{ n = "Carpet Cleaning Extra Large(250sq.ft)";     d = "Professional deep cleaning of extra-large carpets up to 250 sq.ft to remove embedded dirt, stains, and odors." }
    @{ n = "Dining Table Cleaning- 4 Chairs";  d = "Professional cleaning of a dining table with 4 chairs, including surface sanitization and stain removal." }
    @{ n = "Dining Table Cleaning- 5 Chairs";  d = "Professional cleaning of a dining table with 5 chairs, including surface sanitization and stain removal." }
    @{ n = "Dining Table Cleaning- 6 Chairs";  d = "Professional cleaning of a dining table with 6 chairs, including surface sanitization and stain removal." }
    @{ n = "Dining Table Cleaning- 7 Chairs";  d = "Professional cleaning of a dining table with 7 chairs, including surface sanitization and stain removal." }
    @{ n = "Dining Table Cleaning- 9 Chairs";  d = "Professional cleaning of a dining table with 9 chairs, including surface sanitization and stain removal." }
    @{ n = "Dining Table Cleaning- 10 Chairs"; d = "Professional cleaning of a dining table with 10 chairs, including surface sanitization and stain removal." }
    @{ n = "Double Bed Mattress Cleaning"; d = "Deep cleaning and sanitization of a double bed mattress to eliminate dust mites, allergens, and odors." }
    @{ n = "single Bed Mattress Cleaning"; d = "Deep cleaning and sanitization of a single bed mattress for a fresh, hygienic sleep surface." }
    @{ n = "Furniture Wet Wiping";         d = "Thorough wet wipe-down of all furniture surfaces to remove dust, grime, and surface stains." }
    @{ n = "Balcony cleaning";                                 d = "Professional cleaning of balcony floors, railings, and walls to remove dirt, stains, and outdoor grime." }
    @{ n = "Ceiling Fan Cleaning(upto 2)";                     d = "Cleaning of up to 2 ceiling fans including blades and housing to remove accumulated dust." }
    @{ n = "Home Renovation Waste Disposal";                   d = "Efficient collection and disposal of debris and waste generated from home renovation or construction work." }
    @{ n = "Sticker Glue & Rigid Paint Mark Removal- 1 room";  d = "Professional removal of sticker residue and rigid paint marks from walls and surfaces in 1 room." }
    @{ n = "AC Inspection";    d = "Comprehensive inspection of your AC unit to diagnose performance issues, check gas levels, and assess component health." }
    @{ n = "AC Power On Issue"; d = "Expert diagnosis and repair for an air conditioner that fails to turn on or causes power tripping." }
    @{ n = "AC Water Leakage";  d = "Diagnosis and repair of AC water leakage including drain pipe cleaning and internal component inspection." }
    @{ n = "Refrigerator Gas Refill";  d = "Professional refrigerant gas refill to restore optimal cooling performance to your refrigerator." }
    @{ n = "Refrigerator Services";    d = "Comprehensive refrigerator servicing including thermostat check, coil cleaning, and performance evaluation." }
    @{ n = "Microwave Services";       d = "Professional repair and servicing of microwave ovens for heating issues, door faults, and electrical problems." }
    @{ n = "Washing Machine Services"; d = "Expert diagnosis and repair of washing machine issues including spin, drain, and electrical faults." }
    @{ n = "Water Purifier Services";  d = "Servicing and maintenance of water purifiers including filter replacement, UV check, and performance testing." }
    @{ n = "EV Battery Diagnosis";   d = "Comprehensive diagnostic check of your EV battery to assess health, capacity, and identify performance issues." }
    @{ n = "EV Battery Replacement"; d = "Professional replacement of electric vehicle battery packs by certified technicians." }
    @{ n = "EV Charging";            d = "Expert diagnosis and repair of EV charging port and onboard charger issues." }
    @{ n = "EV Inspection";          d = "Full inspection of your electric vehicle including battery, motor, brakes, and onboard electronics." }
    @{ n = "EV Maintenance";         d = "Scheduled maintenance service for electric vehicles to ensure peak performance and long-term reliability." }
    @{ n = "EV Motor Repair";        d = "Professional diagnosis and repair of electric vehicle motor and drivetrain components." }
    @{ n = "EV Repair";              d = "Expert repair services for a wide range of electric vehicle mechanical and electrical problems." }
    @{ n = "Furnished villa basic cleaning upto 1200sqft"; d = "Basic cleaning of a furnished villa up to 1200 sq.ft including sweeping, mopping, dusting, and surface cleaning." }
    @{ n = "Furnished villa basic cleaning upto 2000sqft"; d = "Basic cleaning of a furnished villa up to 2000 sq.ft including sweeping, mopping, dusting, and surface cleaning." }
    @{ n = "Furnished villa basic cleaning upto 3000sqft"; d = "Basic cleaning of a furnished villa up to 3000 sq.ft including sweeping, mopping, dusting, and surface cleaning." }
    @{ n = "Furnished villa basic cleaning upto 4000sqft"; d = "Basic cleaning of a furnished villa up to 4000 sq.ft including sweeping, mopping, dusting, and surface cleaning." }
    @{ n = "Furnished villa basic cleaning upto 5000sqft"; d = "Basic cleaning of a furnished villa up to 5000 sq.ft including sweeping, mopping, dusting, and surface cleaning." }
    @{ n = "Furnished Villa Deep Cleaning 1200sq.ft"; d = "Comprehensive deep cleaning of a furnished villa up to 1200 sq.ft, covering all rooms, surfaces, fans, and fixtures." }
    @{ n = "Furnished Villa Deep Cleaning 2000sq.ft"; d = "Comprehensive deep cleaning of a furnished villa up to 2000 sq.ft, covering all rooms, surfaces, fans, and fixtures." }
    @{ n = "Furnished Villa Deep Cleaning 3000sq.ft"; d = "Comprehensive deep cleaning of a furnished villa up to 3000 sq.ft, covering all rooms, surfaces, fans, and fixtures." }
    @{ n = "Furnished Villa Deep Cleaning 4000sq.ft"; d = "Comprehensive deep cleaning of a furnished villa up to 4000 sq.ft, covering all rooms, surfaces, fans, and fixtures." }
    @{ n = "Furnished Villa Deep Cleaning 5000sq.ft"; d = "Comprehensive deep cleaning of a furnished villa up to 5000 sq.ft, covering all rooms, surfaces, fans, and fixtures." }
    @{ n = "Furnished Villa Deep Cleaning 6000sq.ft"; d = "Comprehensive deep cleaning of a furnished villa up to 6000 sq.ft, covering all rooms, surfaces, fans, and fixtures." }
    @{ n = "Un-Furnished Villa Basic Cleaning 1200sq.ft"; d = "Basic cleaning of an unfurnished villa up to 1200 sq.ft including sweeping, mopping, and surface cleaning." }
    @{ n = "Un-Furnished Villa Basic Cleaning 2000sq.ft"; d = "Basic cleaning of an unfurnished villa up to 2000 sq.ft including sweeping, mopping, and surface cleaning." }
    @{ n = "Un-Furnished Villa Basic Cleaning 3000sq.ft"; d = "Basic cleaning of an unfurnished villa up to 3000 sq.ft including sweeping, mopping, and surface cleaning." }
    @{ n = "Un-Furnished Villa Basic Cleaning 4000sq.ft"; d = "Basic cleaning of an unfurnished villa up to 4000 sq.ft including sweeping, mopping, and surface cleaning." }
    @{ n = "Un-Furnished Villa Basic Cleaning 5000sq.ft"; d = "Basic cleaning of an unfurnished villa up to 5000 sq.ft including sweeping, mopping, and surface cleaning." }
    @{ n = "Un-Furnished Villa Basic Cleaning 6000sq.ft"; d = "Basic cleaning of an unfurnished villa up to 6000 sq.ft including sweeping, mopping, and surface cleaning." }
    @{ n = "Un-Furnished Villa Deep Cleaning 1200sq.ft"; d = "Thorough deep cleaning of an unfurnished villa up to 1200 sq.ft, covering all surfaces and hard-to-reach areas." }
    @{ n = "Un-Furnished Villa Deep Cleaning 2000sq.ft"; d = "Thorough deep cleaning of an unfurnished villa up to 2000 sq.ft, covering all surfaces and hard-to-reach areas." }
    @{ n = "Un-Furnished Villa Deep Cleaning 3000sq.ft"; d = "Thorough deep cleaning of an unfurnished villa up to 3000 sq.ft, covering all surfaces and hard-to-reach areas." }
    @{ n = "Un-Furnished Villa Deep Cleaning 4000sq.ft"; d = "Thorough deep cleaning of an unfurnished villa up to 4000 sq.ft, covering all surfaces and hard-to-reach areas." }
    @{ n = "Un-Furnished Villa Deep Cleaning 5000sq.ft"; d = "Thorough deep cleaning of an unfurnished villa up to 5000 sq.ft, covering all surfaces and hard-to-reach areas." }
    @{ n = "Un-Furnished Villa Deep Cleaning 6000sq.ft"; d = "Thorough deep cleaning of an unfurnished villa up to 6000 sq.ft, covering all surfaces and hard-to-reach areas." }
    @{ n = "Overhead Tank Cleaning (upto 1000Ltrs)";    d = "Professional cleaning and sanitization of overhead water storage tanks up to 1000 liters capacity." }
    @{ n = "Overhead Tank Cleaning (1000-2000Ltrs)";    d = "Professional cleaning and sanitization of overhead water tanks between 1000-2000 liters capacity." }
    @{ n = "Underground Tank Cleaning (1000-1500Ltrs)"; d = "Thorough cleaning and disinfection of underground water storage tanks between 1000-1500 liters." }
    @{ n = "Underground Tank Cleaning (1500-3000Ltrs)"; d = "Thorough cleaning and disinfection of underground water tanks between 1500-3000 liters capacity." }
)

$ok = 0; $fail = 0
foreach ($u in $updates) {
    $encoded = [Uri]::EscapeDataString($u.n)
    $body    = @{ description = $u.d } | ConvertTo-Json -Compress
    try {
        Invoke-RestMethod -Uri "$baseUrl`?name=eq.$encoded" -Headers $headers -Method PATCH -Body $body | Out-Null
        Write-Host "OK  $($u.n)"
        $ok++
    } catch {
        Write-Host "ERR $($u.n) -- $_"
        $fail++
    }
}

Write-Host ""
Write-Host "Done: $ok updated, $fail failed."
