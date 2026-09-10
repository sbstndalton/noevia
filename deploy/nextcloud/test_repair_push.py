import importlib.util, unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('repair',Path(__file__).with_name('repair-push.py'));repair=importlib.util.module_from_spec(spec);spec.loader.exec_module(repair)
class RepairTests(unittest.TestCase):
    def test_only_callback_changes_and_original_image_security_and_mounts_are_preserved(self):
        original={'Config':{'Image':'tag','Env':['KEEP=value','NEXTCLOUD_URL=https://old'],'Labels':{'aio':'yes'}},'Image':'sha256:synthetic','HostConfig':{'Binds':['volume:/var/www/html:ro'],'NetworkMode':'nextcloud-aio','RestartPolicy':{'Name':'unless-stopped'},'ReadonlyRootfs':True},'NetworkSettings':{'Networks':{'nextcloud-aio':{'Aliases':['notify','a'*64]}}}}
        result=repair.replacement(original)
        self.assertEqual(result['Image'],'sha256:synthetic');self.assertEqual(result['HostConfig'],original['HostConfig'])
        self.assertEqual(result['Env'],['KEEP=value','NEXTCLOUD_URL='+repair.INTERNAL])
        self.assertEqual(original['Config']['Env'][1],'NEXTCLOUD_URL=https://old')
        self.assertEqual(result['NetworkingConfig']['EndpointsConfig']['nextcloud-aio']['Aliases'],['notify'])
        self.assertEqual(repair.replacement({**original,'Config':result})['Env'],result['Env'])
if __name__=='__main__':unittest.main()
