import React from 'react';
import {createRoot} from 'react-dom/client';
import Storefront from '../app/storefront';
import Manager from '../app/admin/manager';
import '../app/globals.css';
createRoot(document.getElementById('root')!).render(location.pathname.startsWith('/admin')?<Manager/>:<Storefront/>);
