from mangum import Mangum

from vaakya.main import app

handler = Mangum(app, lifespan="off")
